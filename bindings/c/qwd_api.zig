const std = @import("std");
const pipeline_mod = @import("pipeline");
const bam_pipeline_mod = @import("bam_pipeline");
const pipeline_config_mod = @import("pipeline_config");
const parser_mod = @import("parser");
const mode_mod = @import("mode");

var g_io_instance: std.Io.Threaded = undefined;
var g_io: std.Io = undefined;
var g_initialized: bool = false;

export fn qwd_init() void {
    if (g_initialized) return;
    const allocator = std.heap.c_allocator;
    g_io_instance = std.Io.Threaded.init(allocator, .{});
    g_io = g_io_instance.io();
    g_initialized = true;
}

fn openDirect(path: [*:0]const u8) !std.Io.File {
    return std.Io.Dir.openFile(.cwd(), g_io, std.mem.span(path), .{});
}

export fn qwd_pipeline_run(p: *pipeline_mod.Pipeline, file_path: [*:0]const u8) i32 {
    if (!g_initialized) qwd_init();
    const file = openDirect(file_path) catch return -1;
    defer file.close(g_io);
    p.run(file, g_io) catch return -2;
    p.finalize() catch {};
    return 0;
}

export fn qwd_fastq_qc_ex(file_path: [*:0]const u8, threads: i32, mode: i32, gzip_mode: i32) ?[*:0]const u8 {
    _ = mode; _ = gzip_mode;
    if (!g_initialized) qwd_init();
    const allocator = std.heap.c_allocator;
    var config = pipeline_config_mod.PipelineConfig.default();
    config.threads = if (threads > 0) @intCast(threads) else 1;
    var p = pipeline_mod.Pipeline.init(allocator, config);
    defer p.deinit();
    p.addDefaultStages() catch return null;
    const file = openDirect(file_path) catch return null;
    defer file.close(g_io);
    p.run(file, g_io) catch return null;
    p.finalize() catch {};
    return p.reportJsonAlloc(allocator, g_io) catch null;
}

export fn qwd_fastq_qc_ex_r(file_path_ptr: *[*:0]const u8, threads: *i32, mode: *i32, gzip_mode: *i32, out_buf: [*]u8, max_len: *i32) void {
    _ = mode; _ = gzip_mode;
    if (!g_initialized) qwd_init();
    const allocator = std.heap.c_allocator;
    const path_str = file_path_ptr.*;
    
    var config = pipeline_config_mod.PipelineConfig.default();
    config.threads = if (threads.* > 0) @intCast(threads.*) else 1;
    
    var p = pipeline_mod.Pipeline.init(allocator, config);
    defer p.deinit();
    p.addDefaultStages() catch return;
    
    const file = openDirect(path_str) catch |err| {
        std.debug.print("[C-API-R] Open error: {s}\n", .{@errorName(err)});
        return;
    };
    defer file.close(g_io);
    
    p.run(file, g_io) catch |err| {
        std.debug.print("[C-API-R] Run error: {s}\n", .{@errorName(err)});
        return;
    };
    p.finalize() catch {};
    
    const json = p.reportJsonAlloc(allocator, g_io) catch |err| {
        std.debug.print("[C-API-R] Report error: {s}\n", .{@errorName(err)});
        return;
    };
    defer {
        const span = std.mem.span(json);
        allocator.free(span);
    }
    
    const json_slice = std.mem.span(json);
    const copy_len = @min(json_slice.len, @as(usize, @intCast(max_len.*)) - 1);
    @memcpy(out_buf[0..copy_len], json_slice[0..copy_len]);
    out_buf[copy_len] = 0;
    
    std.debug.print("[C-API-R] Success: {d} reads, {d} bytes copied\n", .{p.read_count, copy_len});
}

export fn qwd_fastq_qc(file_path: [*:0]const u8) ?[*:0]const u8 {
    return qwd_fastq_qc_ex(file_path, 1, 0, 0);
}

export fn qwd_bam_stats(file_path: [*:0]const u8, threads: i32) ?[*:0]const u8 {
    if (!g_initialized) qwd_init();
    const allocator = std.heap.c_allocator;
    _ = threads; // BAM multi-threading not yet implemented in BAM scheduler

    var p = bam_pipeline_mod.BamPipeline.init(allocator);
    defer p.deinit();

    // Add default BAM stages
    const alignment_stats_stage = allocator.create(@import("alignment_stats").AlignmentStatsStage) catch return null;
    alignment_stats_stage.* = .{};
    p.addStage(alignment_stats_stage.stage()) catch return null;

    const file = openDirect(file_path) catch return null;
    defer file.close(g_io);
    p.run(file, g_io) catch return null;
    p.finalize() catch {};
    return p.reportJsonAlloc(allocator, g_io) catch null;
}

export fn qwd_pipeline(config_json: [*:0]const u8, input_path: [*:0]const u8) ?[*:0]const u8 {
    if (!g_initialized) qwd_init();
    const allocator = std.heap.c_allocator;

    const parsed = pipeline_config_mod.PipelineConfig.parseJson(allocator, std.mem.span(config_json)) catch return null;
    defer parsed.deinit();
    
    var p = pipeline_mod.Pipeline.init(allocator, parsed.value);
    defer p.deinit();

    p.addDefaultStages() catch return null;

    const file = openDirect(input_path) catch return null;
    defer file.close(g_io);
    p.run(file, g_io) catch return null;
    p.finalize() catch {};
    return p.reportJsonAlloc(allocator, g_io) catch null;
}

export fn qwd_free_string(s: [*:0]const u8) void {
    const allocator = std.heap.c_allocator;
    allocator.free(std.mem.span(s));
}
