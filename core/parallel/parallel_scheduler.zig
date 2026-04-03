const std = @import("std");
const ring_buffer_mod = @import("ring_buffer");
const fastq_block = @import("fastq_block");
const bitplanes_mod = @import("bitplanes");
const stage_mod = @import("stage");
const parser_mod = @import("parser");

pub const ParallelScheduler = struct {
    sys_allocator: std.mem.Allocator,
    num_threads: usize,
    read_count: usize = 0,

    pub const Chunk = struct {
        kind: enum { columnar, bitplane_batch, raw_bgzf, raw_batch },
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
            raw_batch: struct {
                reads: []parser_mod.Read,
                count: usize,
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
        return .{
            .sys_allocator = sys_allocator,
            .num_threads = num_threads,
        };
    }

    pub fn deinit(self: *ParallelScheduler) void {
        _ = self;
    }

    const ThreadContext = struct {
        scheduler: *ParallelScheduler,
        work_queue: *ring_buffer_mod.RingBuffer(Chunk),
        bgzf_queue: ?*ring_buffer_mod.RingBuffer(Chunk) = null,
        done_flag: *std.atomic.Value(bool),
        stages: []stage_mod.Stage,
        arena: *std.heap.ArenaAllocator,
        bitplanes: *bitplanes_mod.BitplaneCore,
        col_block: *fastq_block.FastqColumnBlock,
        slots: []DecompSlot,
        local_read_count: usize = 0,
    };

    fn workerLoop(ctx_ptr: *ThreadContext) void {
        const allocator = ctx_ptr.scheduler.sys_allocator;
        while (true) {
            var chunk_opt = ctx_ptr.work_queue.pop();
            // Prioritize decompressed/ready work, then bgzf decompression work
            if (chunk_opt == null and ctx_ptr.bgzf_queue != null) {
                chunk_opt = ctx_ptr.bgzf_queue.?.pop();
            }

            if (chunk_opt) |chunk| {
                switch (chunk.kind) {
                    .raw_batch => {
                        const batch = chunk.data.raw_batch;
                        ctx_ptr.local_read_count += batch.count;
                        
                        ctx_ptr.col_block.read_count = batch.count;
                        for (batch.reads[0..batch.count], 0..) |read, rc| {
                            const seq_len = @min(read.seq.len, ctx_ptr.col_block.max_read_len);
                            for (0..seq_len) |p| {
                                ctx_ptr.col_block.bases[p][rc] = read.seq[p];
                                ctx_ptr.col_block.qualities[p][rc] = read.qual[p];
                            }
                            for (seq_len..ctx_ptr.col_block.max_read_len) |p| {
                                ctx_ptr.col_block.bases[p][rc] = 0;
                                ctx_ptr.col_block.qualities[p][rc] = 0;
                            }
                            ctx_ptr.col_block.read_lengths[rc] = @intCast(seq_len);
                        }

                        ctx_ptr.bitplanes.fromColumnBlock(ctx_ptr.col_block);
                        ctx_ptr.bitplanes.cached_fused = null;

                        for (ctx_ptr.stages) |stage| {
                            _ = stage.processBitplanes(ctx_ptr.bitplanes, ctx_ptr.col_block) catch break;
                        }

                        for (batch.reads[0..batch.count]) |read| {
                            allocator.free(read.id);
                            allocator.free(read.seq);
                            allocator.free(read.qual);
                        }
                        allocator.free(batch.reads);
                    },
                    .columnar => {
                        const col = chunk.data.columnar;
                        ctx_ptr.local_read_count += col.read_count;
                        
                        @memcpy(ctx_ptr.bitplanes.plane_a, col.plane_a);
                        @memcpy(ctx_ptr.bitplanes.plane_c, col.plane_c);
                        @memcpy(ctx_ptr.bitplanes.plane_g, col.plane_g);
                        @memcpy(ctx_ptr.bitplanes.plane_t, col.plane_t);
                        @memcpy(ctx_ptr.bitplanes.plane_n, col.plane_n);
                        @memcpy(ctx_ptr.bitplanes.plane_mask, col.plane_mask);
                        @memcpy(ctx_ptr.col_block.read_lengths, col.read_lengths);
                        ctx_ptr.col_block.read_count = col.read_count;
                        
                        const total_bytes = ctx_ptr.col_block.max_read_len * 1024;
                        @memcpy(ctx_ptr.col_block.bases[0].ptr[0..total_bytes], col.bases);
                        @memcpy(ctx_ptr.col_block.qualities[0].ptr[0..total_bytes], col.qualities);

                        for (ctx_ptr.stages) |stage| {
                            _ = stage.processBitplanes(ctx_ptr.bitplanes, ctx_ptr.col_block) catch break;
                        }
                        
                        allocator.free(col.plane_a);
                        allocator.free(col.plane_c);
                        allocator.free(col.plane_g);
                        allocator.free(col.plane_t);
                        allocator.free(col.plane_n);
                        allocator.free(col.plane_mask);
                        allocator.free(col.bases);
                        allocator.free(col.qualities);
                        allocator.free(col.read_lengths);
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
                        
                        if (bgzf.compressed.len == 0) {
                            slot.actual_len = 0;
                            slot.ready.store(true, .release);
                            continue;
                        }

                        const actual_len = @import("deflate_wrapper").DeflateWrapper.decompressBgzfBlock(
                            bgzf.compressed, 
                            slot.decompressed
                        ) catch 0;
                        
                        slot.actual_len = actual_len;
                        slot.ready.store(true, .release);
                        allocator.free(bgzf.compressed);
                    }
                }
            } else {
                if (ctx_ptr.done_flag.load(.acquire)) break;
                // Backoff to prevent high CPU usage when waiting for work
                std.time.sleep(100 * 1000); // 100 microseconds
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
                const cloned = (try master_stage.clone(arena.allocator())) orelse try pipeline_ptr.createStageInstance(arena.allocator(), pipeline_ptr.stage_names.items[t_stages.items.len]);
                try t_stages.append(cloned);
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

        while (true) {
            var reads = try self.sys_allocator.alloc(parser_mod.Read, batch_size);
            var rc: usize = 0;
            while (rc < batch_size) : (rc += 1) {
                const read = (try parser.next(record_buffer)) orelse break;
                reads[rc] = .{
                    .id = try self.sys_allocator.dupe(u8, read.id),
                    .seq = try self.sys_allocator.dupe(u8, read.seq),
                    .qual = try self.sys_allocator.dupe(u8, read.qual),
                    .arena = null,
                };
            }

            if (rc == 0) {
                self.sys_allocator.free(reads);
                break;
            }

            const c = Chunk{ 
                .kind = .raw_batch,
                .data = .{
                    .raw_batch = .{
                        .reads = reads,
                        .count = rc,
                    },
                },
            };

            while (!work_queue.push(c)) {
                std.time.sleep(10 * 1000); // Backoff if queue is full
            }
        }

        done_flag.store(true, .release);
        for (0..self.num_threads) |i| threads[i].join();
        
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
        for (pipeline_ptr.stages.items) |stage| try stage.finalize();
    }

    pub fn run_chunked(self: *ParallelScheduler, chunk_builder: anytype, pipeline_ptr: anytype) !void {
        const queue_depth = 128;
        // work_queue handles decompressed batches (analysis)
        var work_queue = try ring_buffer_mod.RingBuffer(Chunk).init(self.sys_allocator, queue_depth);
        defer work_queue.deinit();
        
        // bgzf_queue handles compressed blocks (decompression)
        var bgzf_queue = try ring_buffer_mod.RingBuffer(Chunk).init(self.sys_allocator, queue_depth);
        defer bgzf_queue.deinit();
        
        var done_flag = std.atomic.Value(bool).init(false);
        var threads = try self.sys_allocator.alloc(std.Thread, self.num_threads);
        defer self.sys_allocator.free(threads);
        var thread_contexts = try self.sys_allocator.alloc(ThreadContext, self.num_threads);
        defer self.sys_allocator.free(thread_contexts);

        const num_slots = self.num_threads * 4;
        const slots = try self.sys_allocator.alloc(DecompSlot, num_slots);
        for (slots) |*slot| {
            slot.* = .{
                .decompressed = try self.sys_allocator.alloc(u8, 256 * 1024),
                .actual_len = 0,
                .ready = std.atomic.Value(bool).init(false),
                .claimed = std.atomic.Value(bool).init(false),
            };
        }
        defer {
            for (slots) |slot| self.sys_allocator.free(slot.decompressed);
            self.sys_allocator.free(slots);
        }

        const batch_size = 1024;
        const max_read_len = 1024;

        for (0..self.num_threads) |t_idx| {
            var arena = try self.sys_allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(self.sys_allocator);

            var t_stages = std.ArrayList(stage_mod.Stage).init(arena.allocator());
            for (pipeline_ptr.stages.items) |master_stage| {
                const cloned = (try master_stage.clone(arena.allocator())) orelse try pipeline_ptr.createStageInstance(arena.allocator(), pipeline_ptr.stage_names.items[t_stages.items.len]);
                try t_stages.append(cloned);
            }

            const col_block = try arena.allocator().create(fastq_block.FastqColumnBlock);
            col_block.* = try fastq_block.FastqColumnBlock.init(arena.allocator(), batch_size, max_read_len);
            const bps = try arena.allocator().create(bitplanes_mod.BitplaneCore);
            bps.* = try bitplanes_mod.BitplaneCore.init(arena.allocator(), batch_size, max_read_len);

            thread_contexts[t_idx] = .{
                .scheduler = self,
                .work_queue = work_queue, 
                .bgzf_queue = bgzf_queue,
                .done_flag = &done_flag,
                .stages = try t_stages.toOwnedSlice(),
                .arena = arena,
                .bitplanes = bps,
                .col_block = col_block,
                .slots = slots,
            };
            threads[t_idx] = try std.Thread.spawn(.{}, workerLoop, .{ &thread_contexts[t_idx] });
        }

        const Feeder = struct {
            pub fn run(builder: anytype, queue: *ring_buffer_mod.RingBuffer(Chunk), s_list: []DecompSlot) void {
                var p_slot: usize = 0;
                while (true) {
                    const chunk_data = builder.nextChunk() catch null orelse {
                        const slot = &s_list[p_slot];
                        while (slot.claimed.load(.acquire)) std.time.sleep(10 * 1000);
                        slot.actual_len = 0;
                        slot.ready.store(true, .release);
                        return;
                    };
                    
                    const slot = &s_list[p_slot];
                    while (slot.claimed.load(.acquire)) std.time.sleep(10 * 1000);
                    slot.claimed.store(true, .release);
                    slot.ready.store(false, .release);
                    
                    const c = Chunk{ .kind = .raw_bgzf, .data = .{ .raw_bgzf = .{ .compressed = chunk_data, .slot_idx = p_slot } } };
                    while (!queue.push(c)) std.time.sleep(10 * 1000);
                    
                    p_slot = (p_slot + 1) % s_list.len;
                }
            }
        };

        const feeder = try std.Thread.spawn(.{}, Feeder.run, .{ chunk_builder, bgzf_queue, slots });

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
                    std.time.sleep(10 * 1000);
                }
                
                if (slot.actual_len == 0) { self_p.eof = true; return 0; }
                
                const remaining = slot.actual_len - self_p.pos;
                const n = @min(dest.len, remaining);
                @memcpy(dest[0..n], slot.decompressed[self_p.pos .. self_p.pos + n]);
                self_p.pos += n;
                
                if (self_p.pos == slot.actual_len) {
                    self_p.pos = 0;
                    slot.ready.store(false, .release);
                    slot.claimed.store(false, .release); 
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

        while (true) {
            var reads = try self.sys_allocator.alloc(parser_mod.Read, batch_size);
            var rc: usize = 0;
            while (rc < batch_size) : (rc += 1) {
                const read = (try p.next(record_buffer)) orelse break;
                reads[rc] = .{
                    .id = try self.sys_allocator.dupe(u8, read.id),
                    .seq = try self.sys_allocator.dupe(u8, read.seq),
                    .qual = try self.sys_allocator.dupe(u8, read.qual),
                    .arena = null,
                };
            }

            if (rc == 0) {
                self.sys_allocator.free(reads);
                break;
            }

            const c = Chunk{ 
                .kind = .raw_batch,
                .data = .{
                    .raw_batch = .{
                        .reads = reads,
                        .count = rc,
                    },
                },
            };

            while (!work_queue.push(c)) {
                std.time.sleep(10 * 1000);
            }
        }

        feeder.join();
        done_flag.store(true, .release);
        for (0..self.num_threads) |i| threads[i].join();
        
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
        for (pipeline_ptr.stages.items) |stage| try stage.finalize();
    }

    pub fn finalize(self: *ParallelScheduler) !void {
        _ = self;
    }

    pub fn report(self: *ParallelScheduler, writer: std.io.AnyWriter) void {
        _ = self; _ = writer;
    }
};
