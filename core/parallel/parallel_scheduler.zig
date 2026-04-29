const std = @import("std");
const mode_mod = @import("mode");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");
const global_allocator = @import("global_allocator");
const parser_mod = @import("parser");
const bgzf_native_reader = @import("bgzf_native_reader");
const stage_mod = @import("stage");
const reader_interface = @import("reader_interface");
const scheduler_interface = @import("scheduler_interface");
const ring_buffer_mod = @import("ring_buffer");
const raw_batch_mod = @import("raw_batch");
const ordered_slots = @import("ordered_slots");
const proxy_reader_mod = @import("proxy_reader");
const simd_transpose = @import("simd_transpose");
const deflate_impl = @import("deflate_impl");
const telemetry = @import("telemetry");

pub const ParallelScheduler = struct {
    allocator: std.mem.Allocator,
    num_threads: usize,
    mode: mode_mod.Mode,
    read_count_atomic: std.atomic.Value(usize),
    
    stages: [32]stage_mod.Stage = undefined,
    stage_count: usize = 0,
    
    telemetry_hook: ?telemetry.TelemetryHookFn = null,
    cancel_signal: ?*u32 = null,

    pub fn init(allocator: std.mem.Allocator, num_threads: usize, mode: mode_mod.Mode, gzip: mode_mod.GzipMode) ParallelScheduler {
        _ = gzip;
        return .{
            .allocator = allocator,
            .num_threads = num_threads,
            .mode = mode,
            .read_count_atomic = std.atomic.Value(usize).init(0),
            .stage_count = 0,
        };
    }

    pub fn deinit(self: *ParallelScheduler) void { _ = self; }

    pub fn addStage(self: *ParallelScheduler, stage: stage_mod.Stage) !void {
        if (self.stage_count >= 32) return error.TooManyStages;
        self.stages[self.stage_count] = stage;
        self.stage_count += 1;
    }

    const BatchQueue = ring_buffer_mod.RingBuffer(*raw_batch_mod.RawBatch);

    const WorkerContext = struct {
        scheduler: *ParallelScheduler,
        slots: *ordered_slots.SlotManager,
        work_queue: *BatchQueue,
        pool_queue: *BatchQueue,
    };

    pub fn run(self: *ParallelScheduler, reader: reader_interface.Reader) !void {
        const io = std.Io{ .userdata = null, .vtable = undefined };

        // 1. Infrastructure
        const slot_count = 64;
        var slots = try ordered_slots.SlotManager.init(self.allocator, slot_count, 128 * 1024);
        defer slots.deinit();

        const queue_cap = 128;
        var work_queue = try BatchQueue.init(self.allocator, queue_cap);
        defer work_queue.deinit();
        var pool_queue = try BatchQueue.init(self.allocator, queue_cap);
        defer pool_queue.deinit();

        const batch_pool = try self.allocator.alloc(raw_batch_mod.RawBatch, queue_cap);
        defer self.allocator.free(batch_pool);
        for (batch_pool) |*b| {
            b.* = try raw_batch_mod.RawBatch.init(self.allocator, 1024);
            _ = pool_queue.push(b);
        }
        defer { for (batch_pool) |*b| b.deinit(self.allocator); }

        // 2. Spawn Dual Pools
        const decomp_threads_n = 2;
        const analysis_threads_n = if (self.num_threads > decomp_threads_n) self.num_threads - decomp_threads_n else 1;
        
        var decomp_threads = try self.allocator.alloc(std.Thread, decomp_threads_n);
        var analysis_threads = try self.allocator.alloc(std.Thread, analysis_threads_n);
        defer self.allocator.free(decomp_threads);
        defer self.allocator.free(analysis_threads);

        const ctx = WorkerContext{
            .scheduler = self,
            .slots = slots,
            .work_queue = work_queue,
            .pool_queue = pool_queue,
        };

        for (0..decomp_threads_n) |i| {
            decomp_threads[i] = try std.Thread.spawn(.{}, decompressionWorker, .{ctx});
        }
        for (0..analysis_threads_n) |i| {
            analysis_threads[i] = try std.Thread.spawn(.{}, analysisWorker, .{ctx});
        }

        // 3. Raw Feeder
        const feeder_thread = try std.Thread.spawn(.{}, feederTask, .{struct {
            allocator: std.mem.Allocator, reader: reader_interface.Reader, slots: *ordered_slots.SlotManager, cancel_signal: ?*u32,
        }{ .allocator = self.allocator, .reader = reader, .slots = slots, .cancel_signal = self.cancel_signal }});

        // 4. Parser (Main Thread)
        var proxy = proxy_reader_mod.ProxyReader.init(slots, io);
        var parser = try parser_mod.FastqParser.init(self.allocator, proxy.reader(), 1024 * 1024);
        defer parser.deinit();

        var total_reads: usize = 0;
        var last_log: usize = 0;
        while (true) {
            if (self.cancel_signal) |sig| if (sig.* == 1) return error.Cancelled;
            var batch = pool_queue.pop() orelse break;
            batch.clear();
            while (batch.count < batch.capacity) {
                const read = parser.next() catch |err| {
                    if (err != error.EndOfStream) std.debug.print("[Parser] ERROR: {any}\n", .{err});
                    break;
                } orelse break;

                if (!batch.add(read.seq, read.qual)) {
                    _ = work_queue.push(batch);
                    total_reads += batch.count;
                    if (total_reads - last_log >= 100000) {
                        std.debug.print("[Parser] Progress: {d} reads\n", .{total_reads});
                        last_log = total_reads;
                    }
                    batch = pool_queue.pop() orelse break;
                    batch.clear();
                    _ = batch.add(read.seq, read.qual);
                }
            }
            if (batch.count == 0) {
                _ = pool_queue.push(batch);
                break;
            }
            _ = work_queue.push(batch);
            total_reads += batch.count;
        }

        std.debug.print("[Parser] Finished. Total reads: {d}\n", .{total_reads});

        // 5. Shutdown Sequence
        feeder_thread.join();
        // slots.signalFeederDone() is now inside feederTask
        
        for (decomp_threads) |t| t.join();
        
        work_queue.shutdown();
        for (analysis_threads) |t| t.join();
    }

    fn feederTask(ctx: anytype) void {
        var blocks: usize = 0;
        
        // 1. Detect Format
        var magic: ?[2]u8 = undefined;
        var magic_buf: [2]u8 = undefined;
        const magic_read = ctx.reader.read(&magic_buf) catch 0;
        
        if (magic_read == 2 and magic_buf[0] == 0x1F and magic_buf[1] == 0x8B) {
            // Validate it's actually BGZF (Check for 'BC' extra field if possible or just try first block)
            magic = magic_buf;
            // BGZF PATH
            var bgzf = bgzf_native_reader.BgzfNativeReader.init(ctx.allocator) catch return;
            defer bgzf.deinit();
            
            while (true) {
                if (ctx.cancel_signal) |sig| if (sig.* == 1) break;
                const block = bgzf.nextBlockHardened(ctx.reader, &magic) catch |err| {
                    if (err != error.EndOfStream) std.debug.print("[Feeder] ERROR: {any}\n", .{err});
                    break;
                } orelse break;

                const slot = ctx.slots.acquireSlotForAssign();
                slot.compressed_data = block.compressed_data;
                ctx.slots.commitAssign();
                blocks += 1;
            }
        } else {
            // PLAIN FASTQ PATH
            // Push the bytes we already read back into the first slot
            while (true) {
                const slot = ctx.slots.acquireSlotForAssign();
                var pos: usize = 0;
            if (blocks == 0 and magic_read > 0) {
                if (magic) |m| {
                    @memcpy(slot.decompressed_data[0..magic_read], m[0..magic_read]);
                }
                pos = magic_read;
            }
                
                const read = ctx.reader.read(slot.decompressed_data[pos..]) catch 0;
                if (read == 0 and pos == 0) {
                    ctx.slots.releaseSlotForAssign(slot);
                    break;
                }
                
                slot.decompressed_len = pos + read;
                slot.compressed_data = null; // Mark as already decompressed
                ctx.slots.commitReady(); // Skip decompression workers
                blocks += 1;
                if (read < slot.decompressed_data.len - pos) break;
            }
        }

        std.debug.print("[Feeder] Done. Blocks: {d}\n", .{blocks});
        ctx.slots.signalFeederDone();
    }

    fn decompressionWorker(ctx: WorkerContext) void {
        while (true) {
            const slot = ctx.slots.getSlotForDecompression() orelse break;
            if (slot.compressed_data) |comp| {
                const actual_out = deflate_impl.decompress(comp, slot.decompressed_data) catch |err| {
                    std.debug.print("[Worker] Decompress ERROR: {any}\n", .{err});
                    slot.decompressed_len = 0;
                    ctx.slots.signalSlotReady(slot);
                    continue;
                };
                slot.decompressed_len = actual_out;
                ctx.slots.signalSlotReady(slot);
            }
        }
    }

    fn analysisWorker(ctx: WorkerContext) void {
        const self = ctx.scheduler;
        var bp_core = bitplanes.BitplaneCore.init(self.allocator, 150, 1024) catch return;
        defer bp_core.deinit();
        var block = fastq_block.FastqColumnBlock.init(self.allocator, 1024, 150) catch return;
        defer block.deinit();

        while (true) {
            const batch = ctx.work_queue.pop() orelse break;
            
            block.clear();
            block.read_count = batch.count;
            var max_len: usize = 0;
            for (batch.reads[0..batch.count], 0..) |read, i| {
                const len = @min(read.seq.len, 150);
                block.read_lengths[i] = @intCast(len);
                if (len > max_len) max_len = len;
                simd_transpose.transposeReadFast(block.bases, block.qualities, i, read.seq, read.qual);
            }
            block.active_max_len = max_len;

            // Dispatch Telemetry only if hook is present
            if (self.telemetry_hook) |hook| {
                bp_core.fromColumnBlock(&block);
                hook(&block, &bp_core, "Analysis", 0);
            }

            for (0..self.stage_count) |stage_idx| {
                // Ensure bitplanes are ready for the first stage
                if (stage_idx == 0 and self.telemetry_hook == null) {
                    bp_core.fromColumnBlock(&block);
                }
                _ = self.stages[stage_idx].processBitplanes(&bp_core, &block) catch {};
            }
            _ = self.read_count_atomic.fetchAdd(batch.count, .monotonic);
            _ = ctx.pool_queue.push(batch);
        }
    }

    pub fn scheduler(self: *ParallelScheduler) scheduler_interface.Scheduler {
        const Gen = struct {
            fn addStage(ctx: *anyopaque, stage: stage_mod.Stage) !void {
                const s: *ParallelScheduler = @ptrCast(@alignCast(ctx));
                return s.addStage(stage);
            }
            fn run(ctx: *anyopaque, reader: reader_interface.Reader) !void {
                const s: *ParallelScheduler = @ptrCast(@alignCast(ctx));
                return s.run(reader);
            }
            fn finalize(ctx: *anyopaque) !void {
                const s: *ParallelScheduler = @ptrCast(@alignCast(ctx));
                return s.finalize();
            }
            fn getReadCount(ctx: *anyopaque) usize {
                const s: *ParallelScheduler = @ptrCast(@alignCast(ctx));
                return s.read_count_atomic.load(.monotonic);
            }
            fn setTelemetry(ctx: *anyopaque, hook: *anyopaque) void {
                const s: *ParallelScheduler = @ptrCast(@alignCast(ctx));
                s.telemetry_hook = @ptrCast(@alignCast(hook));
            }
            fn deinit(ctx: *anyopaque) void {
                const s: *ParallelScheduler = @ptrCast(@alignCast(ctx));
                s.deinit();
            }
        };
        return .{
            .ptr = self,
            .vtable = &.{
                .addStage = Gen.addStage, 
                .run = Gen.run, 
                .finalize = Gen.finalize, 
                .getReadCount = Gen.getReadCount, 
                .setTelemetry = Gen.setTelemetry,
                .deinit = Gen.deinit,
            },
        };
    }
    pub fn finalize(self: *ParallelScheduler) !void { _ = self; }
};
