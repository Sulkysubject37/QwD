const std = @import("std");
const pipeline_mod = @import("pipeline");
const pipeline_config_mod = @import("pipeline_config");
const global_allocator = @import("global_allocator");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");
const parallel_scheduler_mod = @import("parallel_scheduler");
const reader_interface = @import("reader_interface");
const telemetry = @import("telemetry");
const common = @import("common");

// HARDENED C-ABI DEFINITIONS
pub const qwd_telemetry_t = common.qwd_telemetry_t;
pub const qwd_context_t = common.qwd_context_t;

// INTERNAL NATIVE STATE
const DashboardState = struct {
    read_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    gc_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    at_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    n_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    violations: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    var instance: DashboardState = .{};
    var lock: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    fn acquire() void { while (lock.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint(); }
    fn release() void { lock.store(0, .release); }
    var gc_dist: [101]u64 = [_]u64{0} ** 101;
    var len_dist: [1000]u64 = [_]u64{0} ** 1000;
    var heatmap: [150 * 42]u64 = [_]u64{0} ** (150 * 42);
    threadlocal var hook_counter: usize = 0;
};

// THE NATIVE TELEMETRY HOOK
pub fn native_telemetry_hook(
    block: ?*const fastq_block.FastqColumnBlock, 
    bp: ?*const bitplanes.BitplaneCore,
    header: [*:0]const u8,
    thread_id: usize,
) callconv(.c) void {
    _ = header; _ = thread_id;
    if (block == null or bp == null) return;
    const b = block.?;
    const p = bp.?;
    const count = b.read_count;

    _ = DashboardState.instance.read_count.fetchAdd(count, .monotonic);

    DashboardState.hook_counter += 1;
    if (DashboardState.hook_counter % 16 != 0) return;

    var fused: bitplanes.BitplaneCore.FusedResults = .{};
    p.computeFusedInto(count, &fused);

    var local_gc_dist = [_]u64{0} ** 101;
    var local_len_dist = [_]u64{0} ** 1000;
    var local_heatmap = [_]u64{0} ** (150 * 42);

    for (0..count) |i| {
        const len = b.read_lengths[i];
        if (len < 1000) local_len_dist[len] += 1;
        const gc_perc = @as(f32, @floatFromInt(fused.per_read_gc[i])) / @as(f32, @floatFromInt(@max(1, len))) * 100.0;
        const bin = @as(usize, @intFromFloat(@min(100.0, gc_perc)));
        local_gc_dist[bin] += 1;
        for (0..@min(len, 150)) |j| {
            const q = if (b.qualities[j][i] >= 33) b.qualities[j][i] - 33 else b.qualities[j][i];
            local_heatmap[j * 42 + @min(41, q)] += 1;
        }
    }

    DashboardState.acquire();
    defer DashboardState.release();
    _ = DashboardState.instance.gc_count.fetchAdd(fused.gc_count, .monotonic);
    _ = DashboardState.instance.at_count.fetchAdd(fused.a_count + fused.t_count, .monotonic);
    _ = DashboardState.instance.n_count.fetchAdd(fused.n_count, .monotonic);
    _ = DashboardState.instance.violations.fetchAdd(fused.integrity_violations, .monotonic);
    for (0..101) |idx| DashboardState.gc_dist[idx] += local_gc_dist[idx];
    for (0..1000) |idx| DashboardState.len_dist[idx] += local_len_dist[idx];
    for (0..(150 * 42)) |idx| DashboardState.heatmap[idx] += local_heatmap[idx];
}

pub export fn qwd_create() ?*qwd_context_t {
    const ctx = std.heap.page_allocator.create(qwd_context_t) catch return null;
    ctx.* = .{};
    return ctx;
}

pub export fn qwd_init_state(ctx: *qwd_context_t) callconv(.c) void {
    ctx.telemetry_hook = @constCast(@ptrCast(&native_telemetry_hook));
    ctx.cancelled = 0;
    DashboardState.acquire();
    defer DashboardState.release();
    DashboardState.instance.read_count.store(0, .monotonic);
    DashboardState.instance.gc_count.store(0, .monotonic);
    DashboardState.instance.violations.store(0, .monotonic);
    @memset(&DashboardState.gc_dist, 0);
    @memset(&DashboardState.len_dist, 0);
    @memset(&DashboardState.heatmap, 0);
}

pub export fn qwd_get_telemetry(ctx: *qwd_context_t, out: *qwd_telemetry_t) callconv(.c) void {
    @memset(std.mem.asBytes(out), 0);
    out.read_count = DashboardState.instance.read_count.load(.monotonic);
    out.gc_count = DashboardState.instance.gc_count.load(.monotonic);
    out.at_count = DashboardState.instance.at_count.load(.monotonic);
    out.n_count = DashboardState.instance.n_count.load(.monotonic);
    out.violations = DashboardState.instance.violations.load(.monotonic);
    out.total_bases = out.gc_count + out.at_count + out.n_count;
    out.status = ctx.status;
    out.cancelled = ctx.cancelled;
    out.thread_count = ctx.thread_count;
    out.use_exact_mode = ctx.use_exact_mode;
    out.memory_bytes = out.read_count * 128; // Estimated
    DashboardState.acquire();
    defer DashboardState.release();
    @memcpy(&out.gc_distribution, &DashboardState.gc_dist);
    @memcpy(&out.length_distribution, &DashboardState.len_dist);
    @memcpy(&out.quality_heatmap, &DashboardState.heatmap);
}

pub export fn qwd_execute_file(ctx: *qwd_context_t, path: [*:0]const u8) callconv(.c) void {
    ctx.status = 1;
    ctx.cancelled = 0;
    const path_slice = std.mem.span(path);
    _ = std.Thread.spawn(.{}, nativeAnalysisTask, .{ctx, path_slice}) catch { ctx.status = 3; };
}

fn nativeAnalysisTask(ctx: *qwd_context_t, path: []const u8) void {
    const allocator = std.heap.page_allocator;
    var g_alloc = global_allocator.GlobalAllocator.init(allocator, 1500 * 1024 * 1024);
    const engine_allocator = g_alloc.allocator();
    var config = pipeline_config_mod.PipelineConfig.default();
    config.threads = ctx.thread_count;
    config.mode = if (ctx.use_exact_mode == 1) .exact else .fast;
    var pipeline = pipeline_mod.Pipeline.init(engine_allocator, config);
    pipeline.addDefaultStages() catch { ctx.status = 3; return; };
    
    var io_threaded = std.Io.Threaded.init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();
    const file = std.Io.Dir.openFile(std.Io.Dir.cwd(), io, path, .{}) catch { ctx.status = 3; return; };
    defer file.close(io);
    const reader_ctx = reader_interface.Reader.IoReaderContext{ .file = file, .io = io };
    const reader = reader_interface.Reader.fromIoFile(&reader_ctx);
    var scheduler = parallel_scheduler_mod.ParallelScheduler.init(engine_allocator, @intCast(ctx.thread_count), config.mode, .auto);
    scheduler.telemetry_hook = if (ctx.telemetry_hook) |h| @ptrCast(@alignCast(h)) else null;
    scheduler.cancel_signal = &ctx.cancelled;

    pipeline.run(reader, scheduler.scheduler()) catch |err| {
        if (err == error.Cancelled) { ctx.status = 0; return; }
        ctx.status = 3; return;
    };
    pipeline.finalize() catch {};
    if (ctx.status == 1) ctx.status = 2;
}

pub export fn qwd_execute_analysis(ctx: *qwd_context_t, path: [*:0]const u8) callconv(.c) void {
    qwd_execute_file(ctx, path);
}

pub export fn qwd_destroy(ctx: *qwd_context_t) callconv(.c) void { std.heap.page_allocator.destroy(ctx); }
pub export fn qwd_reset_state(ctx: *qwd_context_t) callconv(.c) void { 
    ctx.cancelled = 1; 
    ctx.status = 0; 
}
pub export fn qwd_set_params(ctx: *qwd_context_t, threads: u32, exact: u32, trim_f: u32, trim_t: u32, min_q: f32) callconv(.c) void {
    ctx.thread_count = threads; ctx.use_exact_mode = exact; _ = trim_f; _ = trim_t; _ = min_q;
}
