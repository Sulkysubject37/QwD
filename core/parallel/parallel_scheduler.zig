const std = @import("std");
const parser_mod = @import("parser");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const ring_buffer_mod = @import("ring_buffer");
const bitplanes_mod = @import("bitplanes");
const mode_mod = @import("mode");

pub const ParallelScheduler = struct {
    num_threads: usize,
    sys_allocator: std.mem.Allocator,
    gzip_mode: mode_mod.GzipMode = .AUTO,
    
    // REDUCER STATE
    read_count: usize = 0,

    pub const Chunk = struct {
        kind: enum { columnar, bitplane_batch, raw_bgzf },
        data: union {
            columnar: struct {
                plane_a: []u64,
                plane_c: []u64,
                plane_g: []u64,
                plane_t: []u64,
                plane_n: []u64,
                plane_mask: []u64,
                bases: []u8,
                qualities: []u8,
                read_lengths: []u16,
                read_count: usize,
            },
            bitplane_batch: struct {
                bps: *bitplanes_mod.BitplaneCore,
                block: *fastq_block.FastqColumnBlock,
            },
            raw_bgzf: struct {
                compressed: []u8,
                slot_idx: usize,
            },
        },
    };

    const DecompSlot = struct {
        decompressed: []u8,
        actual_len: usize,
        ready: std.atomic.Value(bool),
        claimed: std.atomic.Value(bool),
    };

    pub fn init(sys_allocator: std.mem.Allocator, num_threads: usize) ParallelScheduler {
        return ParallelScheduler{
            .num_threads = if (num_threads == 0) 1 else num_threads,
            .sys_allocator = sys_allocator,
        };
    }

    pub fn deinit(self: *ParallelScheduler) void {
        _ = self;
    }

    pub fn registerStage(self: *ParallelScheduler, stage: stage_mod.Stage) !void {
        _ = self; _ = stage;
    }

    pub fn process(self: *ParallelScheduler, read: parser_mod.Read) !void {
        _ = self; _ = read;
    }

    const ThreadContext = struct {
        scheduler: *ParallelScheduler,
        work_queue: *ring_buffer_mod.RingBuffer(Chunk),
        done_flag: *std.atomic.Value(bool),
        stages: []stage_mod.Stage,
        arena: *std.heap.ArenaAllocator,
        local_read_count: usize = 0,
        
        bitplanes: *bitplanes_mod.BitplaneCore,
        col_block: *fastq_block.FastqColumnBlock,
        
        // Parallel BGZF Decompression
        slots: []DecompSlot,
    };

    fn workerLoop(ctx_ptr: *ThreadContext) void {
        while (true) {
            if (ctx_ptr.work_queue.pop()) |chunk| {
                switch (chunk.kind) {
                    .columnar => {
                        const col = chunk.data.columnar;
                        ctx_ptr.local_read_count += col.read_count;
                        
                        @memcpy(ctx_ptr.bitplanes.plane_a, col.plane_a);
                        @memcpy(ctx_ptr.bitplanes.plane_c, col.plane_c);
                        @memcpy(ctx_ptr.bitplanes.plane_g, col.plane_g);
                        @memcpy(ctx_ptr.bitplanes.plane_t, col.plane_t);
                        @memcpy(ctx_ptr.bitplanes.plane_n, col.plane_n);
                        @memcpy(ctx_ptr.bitplanes.plane_mask, col.plane_mask);
                        
                        @memcpy(ctx_ptr.col_block.read_lengths[0..col.read_count], col.read_lengths[0..col.read_count]);
                        
                        // Copy raw bases and qualities
                        const total_raw = col.read_count * ctx_ptr.col_block.max_read_len;
                        const dest_bases = ctx_ptr.col_block.bases[0].ptr[0..total_raw];
                        const dest_quals = ctx_ptr.col_block.qualities[0].ptr[0..total_raw];
                        @memcpy(dest_bases, col.bases[0..total_raw]);
                        @memcpy(dest_quals, col.qualities[0..total_raw]);
                        
                        ctx_ptr.col_block.read_count = col.read_count;
                        ctx_ptr.bitplanes.cached_fused = null;

                        for (ctx_ptr.stages) |stage| {
                            _ = stage.processBitplanes(ctx_ptr.bitplanes, ctx_ptr.col_block) catch break;
                        }
                        
                        ctx_ptr.scheduler.sys_allocator.free(col.plane_a);
                        ctx_ptr.scheduler.sys_allocator.free(col.plane_c);
                        ctx_ptr.scheduler.sys_allocator.free(col.plane_g);
                        ctx_ptr.scheduler.sys_allocator.free(col.plane_t);
                        ctx_ptr.scheduler.sys_allocator.free(col.plane_n);
                        ctx_ptr.scheduler.sys_allocator.free(col.plane_mask);
                        ctx_ptr.scheduler.sys_allocator.free(col.bases);
                        ctx_ptr.scheduler.sys_allocator.free(col.qualities);
                        ctx_ptr.scheduler.sys_allocator.free(col.read_lengths);
                    },
                    .bitplane_batch => {
                        const batch = chunk.data.bitplane_batch;
                        ctx_ptr.local_read_count += batch.block.read_count;
                        for (ctx_ptr.stages) |stage| {
                            _ = stage.processBitplanes(batch.bps, batch.block) catch break;
                        }
                    },
                    .raw_bgzf => {
                        const bgzf = chunk.data.raw_bgzf;
                        const slot = &ctx_ptr.slots[bgzf.slot_idx];
                        
                        const actual_len = @import("deflate_wrapper").DeflateWrapper.decompressBgzfBlock(
                            bgzf.compressed, 
                            slot.decompressed
                        ) catch 0;
                        
                        slot.actual_len = actual_len;
                        slot.ready.store(true, .release);
                        ctx_ptr.scheduler.sys_allocator.free(bgzf.compressed);
                    }
                }
            } else {
                if (ctx_ptr.done_flag.load(.acquire)) break;
                std.Thread.yield() catch {};
            }
        }
    }

    pub fn run_parallel(self: *ParallelScheduler, parser: *parser_mod.FastqParser, pipeline_ptr: anytype) !void {
        const queue_depth = 128;
        var work_queue = try ring_buffer_mod.RingBuffer(Chunk).init(self.sys_allocator, queue_depth);
        defer work_queue.deinit();
        
        var done_flag = std.atomic.Value(bool).init(false);
        var threads = try self.sys_allocator.alloc(std.Thread, self.num_threads);
        defer self.sys_allocator.free(threads);
        var thread_contexts = try self.sys_allocator.alloc(ThreadContext, self.num_threads);
        defer self.sys_allocator.free(thread_contexts);

        const batch_size = 1024;
        const max_read_len = 1024;

        for (0..self.num_threads) |t_idx| {
            var arena = try self.sys_allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(self.sys_allocator);

            var t_stages = std.ArrayList(stage_mod.Stage).init(arena.allocator());
            for (pipeline_ptr.stages.items) |master_stage| {
                const cloned = try master_stage.clone(arena.allocator());
                try t_stages.append(cloned orelse try pipeline_ptr.createStageInstance(arena.allocator(), pipeline_ptr.stage_names.items[t_stages.items.len]));
            }

            const col_block = try arena.allocator().create(fastq_block.FastqColumnBlock);
            col_block.* = try fastq_block.FastqColumnBlock.init(arena.allocator(), batch_size, max_read_len);
            const bps = try arena.allocator().create(bitplanes_mod.BitplaneCore);
            bps.* = try bitplanes_mod.BitplaneCore.init(arena.allocator(), batch_size, max_read_len);

            thread_contexts[t_idx] = .{
                .scheduler = self,
                .work_queue = work_queue, 
                .done_flag = &done_flag,
                .stages = try t_stages.toOwnedSlice(),
                .arena = arena,
                .bitplanes = bps,
                .col_block = col_block,
                .slots = &.{},
            };
            threads[t_idx] = try std.Thread.spawn(.{}, workerLoop, .{ &thread_contexts[t_idx] });
        }

        const record_buffer = try self.sys_allocator.alloc(u8, 1024 * 1024);
        defer self.sys_allocator.free(record_buffer);

        var staging_col = try fastq_block.FastqColumnBlock.init(self.sys_allocator, batch_size, max_read_len);
        defer staging_col.deinit();
        var staging_bps = try bitplanes_mod.BitplaneCore.init(self.sys_allocator, batch_size, max_read_len);
        defer staging_bps.deinit();

        while (true) {
            var rc: usize = 0;
            while (rc < batch_size) : (rc += 1) {
                const read = (try parser.next(record_buffer)) orelse break;
                const seq_len = @min(read.seq.len, max_read_len);
                for (0..seq_len) |p| {
                    staging_col.bases[p][rc] = read.seq[p];
                    staging_col.qualities[p][rc] = read.qual[p];
                }
                for (seq_len..max_read_len) |p| {
                    staging_col.bases[p][rc] = 0;
                    staging_col.qualities[p][rc] = 0;
                }
                staging_col.read_lengths[rc] = @intCast(seq_len);
            }

            if (rc == 0) break;

            staging_col.read_count = rc;
            staging_bps.fromColumnBlock(staging_col);

            const total_bytes = max_read_len * batch_size;
            const c = Chunk{ 
                .kind = .columnar,
                .data = .{
                    .columnar = .{
                        .plane_a = try self.sys_allocator.dupe(u64, staging_bps.plane_a),
                        .plane_c = try self.sys_allocator.dupe(u64, staging_bps.plane_c),
                        .plane_g = try self.sys_allocator.dupe(u64, staging_bps.plane_g),
                        .plane_t = try self.sys_allocator.dupe(u64, staging_bps.plane_t),
                        .plane_n = try self.sys_allocator.dupe(u64, staging_bps.plane_n),
                        .plane_mask = try self.sys_allocator.dupe(u64, staging_bps.plane_mask),
                        .bases = try self.sys_allocator.dupe(u8, staging_col.bases[0].ptr[0..total_bytes]),
                        .qualities = try self.sys_allocator.dupe(u8, staging_col.qualities[0].ptr[0..total_bytes]),
                        .read_lengths = try self.sys_allocator.dupe(u16, staging_col.read_lengths),
                        .read_count = rc,
                    },
                },
            };

            while (!work_queue.push(c)) {
                std.Thread.yield() catch {};
            }
        }

        done_flag.store(true, .release);
        for (0..self.num_threads) |i| threads[i].join();
        
        // --- REDUCE: MERGE WORKER STATE INTO MASTER PIPELINE ---
        pipeline_ptr.read_count = 0;
        for (0..self.num_threads) |i| {
            var ctx = &thread_contexts[i];
            pipeline_ptr.read_count += ctx.local_read_count;
            for (0..pipeline_ptr.stages.items.len) |s_idx| {
                try pipeline_ptr.stages.items[s_idx].merge(ctx.stages[s_idx]);
            }
            ctx.arena.deinit();
            self.sys_allocator.destroy(ctx.arena);
        }
        
        self.read_count = pipeline_ptr.read_count;
        
        // Finalize Master Stages
        for (pipeline_ptr.stages.items) |stage| {
            try stage.finalize();
        }
    }

    pub fn run_chunked(self: *ParallelScheduler, chunk_builder: anytype, pipeline_ptr: anytype) !void {
        const queue_depth = 128;
        var work_queue = try ring_buffer_mod.RingBuffer(Chunk).init(self.sys_allocator, queue_depth);
        defer work_queue.deinit();
        
        var done_flag = std.atomic.Value(bool).init(false);
        var threads = try self.sys_allocator.alloc(std.Thread, self.num_threads);
        defer self.sys_allocator.free(threads);
        var thread_contexts = try self.sys_allocator.alloc(ThreadContext, self.num_threads);
        defer self.sys_allocator.free(thread_contexts);

        // Ordered Decompression Slots
        const num_slots = self.num_threads * 4;
        const slots = try self.sys_allocator.alloc(DecompSlot, num_slots);
        defer self.sys_allocator.free(slots);
        for (slots) |*slot| {
            slot.* = .{
                .decompressed = try self.sys_allocator.alloc(u8, 128 * 1024),
                .actual_len = 0,
                .ready = std.atomic.Value(bool).init(false),
                .claimed = std.atomic.Value(bool).init(false),
            };
        }
        defer {
            for (slots) |slot| self.sys_allocator.free(slot.decompressed);
        }

        const batch_size = 1024;
        const max_read_len = 1024;

        // Init Workers
        for (0..self.num_threads) |t_idx| {
            var arena = try self.sys_allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(self.sys_allocator);

            var t_stages = std.ArrayList(stage_mod.Stage).init(arena.allocator());
            for (pipeline_ptr.stages.items) |master_stage| {
                const cloned = try master_stage.clone(arena.allocator());
                try t_stages.append(cloned orelse try pipeline_ptr.createStageInstance(arena.allocator(), pipeline_ptr.stage_names.items[t_stages.items.len]));
            }

            const col_block = try arena.allocator().create(fastq_block.FastqColumnBlock);
            col_block.* = try fastq_block.FastqColumnBlock.init(arena.allocator(), batch_size, max_read_len);
            const bps = try arena.allocator().create(bitplanes_mod.BitplaneCore);
            bps.* = try bitplanes_mod.BitplaneCore.init(arena.allocator(), batch_size, max_read_len);

            thread_contexts[t_idx] = .{
                .scheduler = self,
                .work_queue = work_queue, 
                .done_flag = &done_flag,
                .stages = try t_stages.toOwnedSlice(),
                .arena = arena,
                .bitplanes = bps,
                .col_block = col_block,
                .slots = slots,
            };
            threads[t_idx] = try std.Thread.spawn(.{}, workerLoop, .{ &thread_contexts[t_idx] });
        }

        // Background thread to fill slots
        var producer_slot: usize = 0;
        const Feeder = struct {
            pub fn run(builder: anytype, queue: *ring_buffer_mod.RingBuffer(Chunk), p_slot: *usize, n_slots: usize, s_list: []DecompSlot) void {
                while (true) {
                    const chunk_data = builder.nextChunk() catch null orelse {
                        // EOF block
                        const slot = &s_list[p_slot.*];
                        // WAIT for slot to be unclaimed
                        while (slot.claimed.load(.acquire)) std.Thread.yield() catch {};
                        slot.claimed.store(true, .release);
                        
                        const c = Chunk{ .kind = .raw_bgzf, .data = .{ .raw_bgzf = .{ .compressed = &.{}, .slot_idx = p_slot.* } } };
                        while (!queue.push(c)) std.Thread.yield() catch {};
                        return;
                    };
                    
                    const slot = &s_list[p_slot.*];
                    // WAIT for slot to be available
                    while (slot.claimed.load(.acquire)) std.Thread.yield() catch {};
                    slot.claimed.store(true, .release);
                    
                    const c = Chunk{ .kind = .raw_bgzf, .data = .{ .raw_bgzf = .{ .compressed = chunk_data, .slot_idx = p_slot.* } } };
                    while (!queue.push(c)) std.Thread.yield() catch {};
                    
                    p_slot.* = (p_slot.* + 1) % n_slots;
                }
            }
        };

        const feeder = try std.Thread.spawn(.{}, Feeder.run, .{ chunk_builder, work_queue, &producer_slot, num_slots, slots });

        // Main Parser Loop (Sequential parsing from ordered decompressed stream)
        var consumer_slot: usize = 0;
        const ProxyReader = struct {
            slots: []DecompSlot,
            c_slot: *usize,
            pos: usize = 0,
            eof: bool = false,
            
            pub fn read(ctx: *const anyopaque, dest: []u8) anyerror!usize {
                var self_p: *@This() = @constCast(@ptrCast(@alignCast(ctx)));
                if (self_p.eof) return 0;
                
                const slot = &self_p.slots[self_p.c_slot.*];
                while (!slot.ready.load(.acquire)) {
                    std.Thread.yield() catch {};
                }
                
                if (slot.actual_len == 0) { self_p.eof = true; return 0; }
                
                const remaining = slot.actual_len - self_p.pos;
                const n = @min(dest.len, remaining);
                @memcpy(dest[0..n], slot.decompressed[self_p.pos .. self_p.pos + n]);
                self_p.pos += n;
                
                if (self_p.pos == slot.actual_len) {
                    self_p.pos = 0;
                    slot.ready.store(false, .release);
                    slot.claimed.store(false, .release); // Release for recycling
                    self_p.c_slot.* = (self_p.c_slot.* + 1) % self_p.slots.len;
                }
                return n;
            }
        };

        var proxy = ProxyReader{ .slots = slots, .c_slot = &consumer_slot };
        const any_reader = std.io.AnyReader{ .context = &proxy, .readFn = ProxyReader.read };
        
        var arena_parser = std.heap.ArenaAllocator.init(self.sys_allocator);
        defer arena_parser.deinit();
        var br = try @import("block_reader").BlockReader.init(arena_parser.allocator(), any_reader, 256 * 1024);
        var p = parser_mod.FastqParser{ .reader = &br, .allocator = arena_parser.allocator() };

        const record_buffer = try self.sys_allocator.alloc(u8, 1024 * 1024);
        defer self.sys_allocator.free(record_buffer);

        var staging_col = try fastq_block.FastqColumnBlock.init(self.sys_allocator, batch_size, max_read_len);
        defer staging_col.deinit();
        var staging_bps = try bitplanes_mod.BitplaneCore.init(self.sys_allocator, batch_size, max_read_len);
        defer staging_bps.deinit();

        while (true) {
            var rc: usize = 0;
            while (rc < batch_size) : (rc += 1) {
                const read = (try p.next(record_buffer)) orelse break;
                const seq_len = @min(read.seq.len, max_read_len);
                for (0..seq_len) |pos| {
                    staging_col.bases[pos][rc] = read.seq[pos];
                    staging_col.qualities[pos][rc] = read.qual[pos];
                }
                for (seq_len..max_read_len) |pos| {
                    staging_col.bases[pos][rc] = 0;
                    staging_col.qualities[pos][rc] = 0;
                }
                staging_col.read_lengths[rc] = @intCast(seq_len);
            }
            if (rc == 0) break;

            staging_col.read_count = rc;
            staging_bps.fromColumnBlock(staging_col);

            const total_bytes = max_read_len * batch_size;
            const c = Chunk{
                .kind = .columnar,
                .data = .{
                    .columnar = .{
                        .plane_a = try self.sys_allocator.dupe(u64, staging_bps.plane_a),
                        .plane_c = try self.sys_allocator.dupe(u64, staging_bps.plane_c),
                        .plane_g = try self.sys_allocator.dupe(u64, staging_bps.plane_g),
                        .plane_t = try self.sys_allocator.dupe(u64, staging_bps.plane_t),
                        .plane_n = try self.sys_allocator.dupe(u64, staging_bps.plane_n),
                        .plane_mask = try self.sys_allocator.dupe(u64, staging_bps.plane_mask),
                        .bases = try self.sys_allocator.dupe(u8, staging_col.bases[0].ptr[0..total_bytes]),
                        .qualities = try self.sys_allocator.dupe(u8, staging_col.qualities[0].ptr[0..total_bytes]),
                        .read_lengths = try self.sys_allocator.dupe(u16, staging_col.read_lengths),
                        .read_count = rc,
                    },
                },
            };
            while (!work_queue.push(c)) std.Thread.yield() catch {};
        }

        feeder.join();
        done_flag.store(true, .release);
        for (0..self.num_threads) |i| threads[i].join();
        
        // --- REDUCE ---
        pipeline_ptr.read_count = 0;
        for (0..self.num_threads) |i| {
            var ctx = &thread_contexts[i];
            pipeline_ptr.read_count += ctx.local_read_count;
            for (0..pipeline_ptr.stages.items.len) |s_idx| {
                try pipeline_ptr.stages.items[s_idx].merge(ctx.stages[s_idx]);
            }
            ctx.arena.deinit();
            self.sys_allocator.destroy(ctx.arena);
        }
        
        self.read_count = pipeline_ptr.read_count;
        for (pipeline_ptr.stages.items) |stage| {
            try stage.finalize();
        }
    }

    pub fn finalize(self: *ParallelScheduler) !void {
        _ = self;
    }

    pub fn report(self: *ParallelScheduler, writer: std.io.AnyWriter) void {
        _ = self; _ = writer;
    }

};
