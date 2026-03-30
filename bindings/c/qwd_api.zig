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

/// Extended FASTQ QC API
/// mode: 0 = exact, 1 = approx
/// gzip_mode: 0 = auto, 1 = libdeflate, 2 = chunked, 3 = compat
pub export fn qwd_fastq_qc_ex(path: [*:0]const u8, threads: c_int, mode: c_int, gzip_mode: c_int) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();
    const file_path = std.mem.span(path);
    @import("entropy_lut").initGlobal();
    
    var file = std.fs.cwd().openFile(file_path, .{}) catch return allocError(allocator, "File not found");
    defer file.close();

    const analysis_mode: mode_mod.Mode = if (mode == 1) .APPROX else .EXACT;
    const gz_mode: mode_mod.GzipMode = switch (gzip_mode) {
        1 => .LIBDEFLATE,
        2 => .CHUNKED,
        3 => .COMPAT,
        4 => .NATIVE_QWD,
        else => .AUTO,
    };

    var fr = file.reader();
    var parser = if (std.mem.endsWith(u8, file_path, ".gz")) blk: {
        break :blk parser_mod.FastqParser.initGzip(arena_allocator, fr.any(), 1024 * 1024, gz_mode) catch return allocError(allocator, "Gzip Init Failed");
    } else if (analysis_mode == .APPROX) blk: {
        break :blk parser_mod.FastqParser.initMmap(arena_allocator, file) catch return allocError(allocator, "Mmap failed");
    } else blk: {
        break :blk parser_mod.FastqParser.init(arena_allocator, fr.any(), 1024 * 1024) catch return allocError(allocator, "Parser init failed");
    };
    defer parser.deinit();

    var pipeline = pipeline_mod.Pipeline.init(arena_allocator, null);
    pipeline.mode = analysis_mode;
    defer pipeline.deinit();
    
    pipeline.addStage("basic_stats") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("per_base_quality") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("nucleotide_composition") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("gc_distribution") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("length_distribution") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("n_statistics") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("entropy") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("kmer_spectrum") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("overrepresented") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("duplication") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("adapter_detect") catch return allocError(allocator, "Stage init failed");

    const num_threads: usize = if (threads <= 0) std.Thread.getCpuCount() catch 1 else @intCast(threads);
    pipeline.setupSchedulers(num_threads) catch return allocError(allocator, "Scheduler setup failed");

    if (num_threads > 1 or analysis_mode == .APPROX) {
        const chunk_builder_mod = @import("chunk_builder");
        var chunk_builder = chunk_builder_mod.ChunkBuilder.init(&parser, 256 * 1024);
        pipeline.run_chunked(&chunk_builder) catch |err| return allocError(allocator, @errorName(err));
    } else {
        const record_buffer = arena_allocator.alloc(u8, 65536) catch return allocError(allocator, "Buffer alloc failed");
        while (true) {
            if (parser.next(record_buffer) catch null) |read| {
                if (pipeline.parallel_scheduler) |*ps| {
                    ps.process(read) catch return allocError(allocator, "Processing error");
                } else if (pipeline.scheduler) |*s| {
                    s.process(read) catch return allocError(allocator, "Processing error");
                }
            } else break;
        }
    }

    pipeline.finalize() catch return allocError(allocator, "Pipeline finalize error");

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    if (pipeline.parallel_scheduler) |*ps| {
        structured_output.writeJsonReport(ps, buffer.writer().any()) catch return allocError(allocator, "JSON report failed");
    } else if (pipeline.scheduler) |*s| {
        structured_output.writeJsonReport(s, buffer.writer().any()) catch return allocError(allocator, "JSON report failed");
    }

    return std.fmt.allocPrintZ(allocator, "{s}", .{buffer.items}) catch return "{\"error\":\"final alloc failure\"}";
}

pub export fn qwd_bam_stats(path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const file_path = std.mem.span(path);
    var file = std.fs.cwd().openFile(file_path, .{}) catch return allocError(allocator, "File not found");
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();

    var bam_pipeline = bam_pipeline_mod.BamPipeline.init(arena_allocator);
    defer bam_pipeline.deinit();
    bam_pipeline.addDefaultStages() catch return allocError(allocator, "BAM stage init failed");

    var bam_reader = bam_reader_mod.BamReader.init(arena_allocator, reader.any()) catch return allocError(allocator, "BAM parser failed");
    
    var record_buf: [4096]u8 = undefined;
    while (bam_reader.next(&record_buf) catch null) |record| {
        bam_pipeline.run(record) catch break;
    }
    bam_pipeline.finalize() catch {};

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    structured_output.writeJsonReport(&bam_pipeline.scheduler, buffer.writer().any()) catch return allocError(allocator, "JSON report failed");

    return std.fmt.allocPrintZ(allocator, "{s}", .{buffer.items}) catch return "{\"error\":\"final alloc failure\"}";
}

pub export fn qwd_pipeline(config_path: [*:0]const u8, input_path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();
    const c_path = std.mem.span(config_path);
    const i_path = std.mem.span(input_path);
    @import("entropy_lut").initGlobal();

    const config_data = std.fs.cwd().readFileAlloc(arena_allocator, c_path, 1024 * 1024) catch return allocError(allocator, "Config file not found");
    const config = pipeline_config_mod.PipelineConfig.parseJson(arena_allocator, config_data) catch return allocError(allocator, "Invalid config JSON");

    var pipeline = pipeline_mod.Pipeline.init(arena_allocator, null);
    defer pipeline.deinit();

    for (config.value.pipeline) |stage_name| {
        pipeline.addStage(stage_name) catch return allocError(allocator, "Stage init failed");
    }

    pipeline.setupSchedulers(1) catch return allocError(allocator, "Scheduler setup failed");

    const file = std.fs.cwd().openFile(i_path, .{}) catch return allocError(allocator, "Input file not found");
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();

    var parser = parser_mod.FastqParser.init(arena_allocator, reader.any(), 65536) catch return allocError(allocator, "Parser init failed");
    defer parser.deinit();

    const record_buffer = arena_allocator.alloc(u8, 65536) catch return allocError(allocator, "Buffer alloc failed");

    while (true) {
        if (parser.next(record_buffer) catch null) |read| {
            if (pipeline.parallel_scheduler) |*ps| {
                ps.process(read) catch return allocError(allocator, "Processing error");
            } else if (pipeline.scheduler) |*s| {
                s.process(read) catch return allocError(allocator, "Processing error");
            }
        } else break;
    }

    pipeline.finalize() catch return allocError(allocator, "Pipeline finalize error");

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    if (pipeline.parallel_scheduler) |*ps| {
        structured_output.writeJsonReport(ps, buffer.writer().any()) catch return allocError(allocator, "JSON report failed");
    } else if (pipeline.scheduler) |*s| {
        structured_output.writeJsonReport(s, buffer.writer().any()) catch return allocError(allocator, "JSON report failed");
    }

    return std.fmt.allocPrintZ(allocator, "{s}", .{buffer.items}) catch return "{\"error\":\"final alloc failure\"}";
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
    const res = qwd_bam_stats(p);
    defer qwd_free_string(res);

    const len = std.mem.indexOfSentinel(u8, 0, res);
    const m_len: usize = @intCast(max_len[0]);
    if (m_len > 0) {
        const copy_len = @min(len, m_len - 1);
        @memcpy(out[0..copy_len], res[0..copy_len]);
        out[copy_len] = 0;
    }
}
