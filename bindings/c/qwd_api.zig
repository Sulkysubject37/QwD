const std = @import("std");
const pipeline_mod = @import("pipeline");
const pipeline_config_mod = @import("pipeline_config");
const parser_mod = @import("parser");
const bam_pipeline_mod = @import("bam_pipeline");
const bam_reader_mod = @import("bam_reader");
const allocator_mod = @import("allocator");
const structured_output = @import("structured_output");
const mode_mod = @import("mode");

fn allocError(allocator: std.mem.Allocator, msg: []const u8) [*:0]const u8 {
    const error_json = std.fmt.allocPrintZ(allocator, "{{\"error\": \"{s}\"}}", .{msg}) catch return "{\"error\":\"critical memory failure\"}";
    return error_json;
}

pub export fn qwd_fastq_qc(path: [*:0]const u8) [*:0]const u8 {
    return qwd_fastq_qc_ex(path, 1, 0, 0); // exact, 1 thread, auto gzip
}

pub export fn qwd_fastq_qc_fast(path: [*:0]const u8, threads: c_int) [*:0]const u8 {
    return qwd_fastq_qc_ex(path, threads, 1, 0); // approx, threads, auto gzip
}

pub export fn qwd_fastq_qc_ex(path: [*:0]const u8, threads: c_int, mode: c_int, gzip_mode: c_int) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    const file_path = std.mem.span(path);
    @import("entropy_lut").initGlobal();
    
    var file = std.fs.cwd().openFile(file_path, .{}) catch return allocError(allocator, "File not found");
    defer file.close();

    const analysis_mode: mode_mod.Mode = if (mode == 1) .APPROX else .EXACT;
    const gz_mode: mode_mod.GzipMode = switch (gzip_mode) {
        1 => .NATIVE,
        2 => .LIBDEFLATE,
        3 => .CHUNKED,
        4 => .COMPAT,
        else => .AUTO,
    };

    var pipeline = pipeline_mod.Pipeline.init(allocator, null);
    pipeline.mode = analysis_mode;
    pipeline.gzip_mode = gz_mode;
    
    pipeline.addStage("basic_stats") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("nucleotide_composition") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("gc_distribution") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("length_distribution") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("kmer_spectrum") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("quality_dist") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("taxed") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("overrepresented") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("duplication") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("per_base_quality") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("adapter_detect") catch return allocError(allocator, "Stage init failed");

    const num_threads: usize = if (threads <= 0) std.Thread.getCpuCount() catch 1 else @intCast(threads);
    pipeline.setupSchedulers(num_threads) catch return allocError(allocator, "Scheduler setup failed");

    const is_gz = std.mem.endsWith(u8, file_path, ".gz");
    pipeline.run(file, is_gz) catch |err| return allocError(allocator, @errorName(err));

    pipeline.finalize() catch return allocError(allocator, "Pipeline finalize error");

    const json = pipeline.reportJsonAlloc(allocator) catch return allocError(allocator, "JSON allocation failed");
    pipeline.deinit();
    return json;
}

pub export fn qwd_bam_stats(path: [*:0]const u8, threads: c_int) [*:0]const u8 {
    _ = threads;
    const allocator = std.heap.c_allocator;
    const file_path = std.mem.span(path);

    var file = std.fs.cwd().openFile(file_path, .{}) catch return allocError(allocator, "File not found");
    defer file.close();

    var bam_pipeline = bam_pipeline_mod.BamPipeline.init(allocator);
    bam_pipeline.addDefaultStages() catch return allocError(allocator, "BAM stage setup failed");

    var reader = bam_reader_mod.BamReader.init(allocator, file.reader().any()) catch return allocError(allocator, "BAM Reader Init failed");
    defer reader.deinit();

    const record_buffer = allocator.alloc(u8, 1024 * 1024) catch return allocError(allocator, "BAM buffer alloc failed");
    defer allocator.free(record_buffer);
    while (reader.next(record_buffer) catch return allocError(allocator, "BAM read failed")) |record| {
        bam_pipeline.run(record) catch return allocError(allocator, "BAM processing failed");
    }
    bam_pipeline.finalize() catch return allocError(allocator, "BAM Finalize failed");

    const json = bam_pipeline.reportJsonAlloc(allocator) catch return allocError(allocator, "JSON allocation failed");
    bam_pipeline.deinit();
    return json;
}

pub export fn qwd_pipeline(config_path: [*:0]const u8, input_path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    const c_path = std.mem.span(config_path);
    const i_path = std.mem.span(input_path);
    @import("entropy_lut").initGlobal();

    const config_data = std.fs.cwd().readFileAlloc(allocator, c_path, 1024 * 1024) catch return allocError(allocator, "Config file not found");
    defer allocator.free(config_data);
    const config = pipeline_config_mod.PipelineConfig.parseJson(allocator, config_data) catch return allocError(allocator, "Invalid config JSON");
    defer config.deinit();

    var pipeline = pipeline_mod.Pipeline.init(allocator, config.value);
    
    for (config.value.pipeline) |stage_name| {
        pipeline.addStage(stage_name) catch return allocError(allocator, "Stage init failed");
    }

    pipeline.setupSchedulers(1) catch return allocError(allocator, "Scheduler setup failed");

    const file = std.fs.cwd().openFile(i_path, .{}) catch return allocError(allocator, "Input file not found");
    defer file.close();

    const is_gz = std.mem.endsWith(u8, i_path, ".gz");
    pipeline.run(file, is_gz) catch |err| return allocError(allocator, @errorName(err));

    pipeline.finalize() catch return allocError(allocator, "Pipeline finalize error");

    const json = pipeline.reportJsonAlloc(allocator) catch return allocError(allocator, "JSON allocation failed");
    pipeline.deinit();
    return json;
}

pub export fn qwd_run_json_config(config_json: [*:0]const u8, input_path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    const json_data = std.mem.span(config_json);
    const i_path = std.mem.span(input_path);
    @import("entropy_lut").initGlobal();

    const config = pipeline_config_mod.PipelineConfig.parseJson(allocator, json_data) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Invalid config JSON: {s}", .{@errorName(err)}) catch return allocError(allocator, "JSON Error");
        defer allocator.free(msg);
        return allocError(allocator, msg);
    };
    defer config.deinit();

    var pipeline = pipeline_mod.Pipeline.init(allocator, config.value);
    
    for (config.value.pipeline) |stage_name| {
        pipeline.addStage(stage_name) catch return allocError(allocator, "Stage init failed");
    }

    const num_threads = std.Thread.getCpuCount() catch 1;
    pipeline.setupSchedulers(num_threads) catch return allocError(allocator, "Scheduler setup failed");

    var file = std.fs.cwd().openFile(i_path, .{}) catch return allocError(allocator, "Input file not found");
    defer file.close();

    const is_gz = std.mem.endsWith(u8, i_path, ".gz");
    pipeline.run(file, is_gz) catch |err| return allocError(allocator, @errorName(err));

    pipeline.finalize() catch return allocError(allocator, "Pipeline finalize error");

    const json = pipeline.reportJsonAlloc(allocator) catch return allocError(allocator, "JSON allocation failed");
    pipeline.deinit();
    return json;
}

pub export fn qwd_free_string(ptr: [*:0]const u8) void {
    const allocator = std.heap.c_allocator;
    const len = std.mem.indexOfSentinel(u8, 0, ptr);
    allocator.free(ptr[0..len + 1]);
}

pub export fn qwd_fastq_qc_r(path: [*c]const [*c]const u8, out: [*c]u8, max_len: [*c]const c_int) void {
    const p = path[0];
    const res = qwd_fastq_qc(p);
    defer qwd_free_string(res);

    const len = std.mem.indexOfSentinel(u8, 0, res);
    const m_len: usize = @intCast(max_len[0]);
    if (m_len > 0) {
        const copy_len = @min(len, m_len - 1);
        @memcpy(out[0..copy_len], res[0..copy_len]);
        out[copy_len] = 0;
    }
}

pub export fn qwd_fastq_qc_fast_r(path: [*c]const [*c]const u8, threads: [*c]const c_int, out: [*c]u8, max_len: [*c]const c_int) void {
    const p = path[0];
    const t = threads[0];
    const res = qwd_fastq_qc_fast(p, t);
    defer qwd_free_string(res);

    const len = std.mem.indexOfSentinel(u8, 0, res);
    const m_len: usize = @intCast(max_len[0]);
    if (m_len > 0) {
        const copy_len = @min(len, m_len - 1);
        @memcpy(out[0..copy_len], res[0..copy_len]);
        out[copy_len] = 0;
    }
}

pub export fn qwd_fastq_qc_ex_r(path: [*c]const [*c]const u8, threads: [*c]const c_int, mode: [*c]const c_int, gzip_mode: [*c]const c_int, out: [*c]u8, max_len: [*c]const c_int) void {
    const p = path[0];
    const t = threads[0];
    const m = mode[0];
    const gz = gzip_mode[0];
    const res = qwd_fastq_qc_ex(p, t, m, gz);
    defer qwd_free_string(res);

    const len = std.mem.indexOfSentinel(u8, 0, res);
    const m_len: usize = @intCast(max_len[0]);
    if (m_len > 0) {
        const copy_len = @min(len, m_len - 1);
        @memcpy(out[0..copy_len], res[0..copy_len]);
        out[copy_len] = 0;
    }
}

pub export fn qwd_bam_stats_r(path: [*c]const [*c]const u8, out: [*c]u8, max_len: [*c]const c_int) void {
    const p = path[0];
    const res = qwd_bam_stats(p, 1);
    defer qwd_free_string(res);

    const len = std.mem.indexOfSentinel(u8, 0, res);
    const m_len: usize = @intCast(max_len[0]);
    if (m_len > 0) {
        const copy_len = @min(len, m_len - 1);
        @memcpy(out[0..copy_len], res[0..copy_len]);
        out[copy_len] = 0;
    }
}
