const std = @import("std");
const pipeline_mod = @import("pipeline");
const parser_mod = @import("parser");
const bam_pipeline_mod = @import("bam_pipeline");
const bam_reader_mod = @import("bam_reader");
const allocator_mod = @import("allocator");
const structured_output = @import("structured_output");

fn allocError(allocator: std.mem.Allocator, msg: []const u8) [*:0]const u8 {
    const error_json = std.fmt.allocPrintZ(allocator, "{{\"error\": \"{s}\"}}", .{msg}) catch return "{\"error\":\"critical memory failure\"}";
    return error_json;
}

pub export fn qwd_fastq_qc(path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const file_path = std.mem.span(path);
    var file = std.fs.cwd().openFile(file_path, .{}) catch return allocError(allocator, "File not found");
    defer file.close();

    var parser = parser_mod.FastqParser.init(arena_allocator, file, 65536) catch return allocError(allocator, "Parser init failed");
    defer parser.deinit();

    var pipeline = pipeline_mod.Pipeline.init(arena_allocator, null);
    defer pipeline.deinit();
    pipeline.setupSchedulers(1) catch return allocError(allocator, "Scheduler setup failed");
    
    pipeline.addStage("basic-stats") catch return allocError(allocator, "Stage init failed");
    pipeline.addStage("per-base-quality") catch return allocError(allocator, "Stage init failed");

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

pub export fn qwd_bam_stats(path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const file_path = std.mem.span(path);
    var file = std.fs.cwd().openFile(file_path, .{}) catch return allocError(allocator, "File not found");
    defer file.close();

    var bam_pipeline = bam_pipeline_mod.BamPipeline.init(arena_allocator);
    defer bam_pipeline.deinit();
    bam_pipeline.addDefaultStages() catch return allocError(allocator, "BAM stage init failed");

    var bam_reader = bam_reader_mod.BamReader.init(arena_allocator, file.reader().any()) catch return allocError(allocator, "BAM parser failed");
    
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

pub export fn qwd_pipeline(config_json_path: [*:0]const u8, input_path: [*:0]const u8) [*:0]const u8 {
    _ = config_json_path;
    _ = input_path;
    const allocator = std.heap.c_allocator;
    return allocError(allocator, "qwd_pipeline not fully implemented in C API yet");
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
