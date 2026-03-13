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

    var buffered_reader = std.io.bufferedReader(file.reader());
    const reader = buffered_reader.reader().any();

    var parser = parser_mod.FastqParser.init(arena_allocator, reader, 65536) catch return allocError(allocator, "Parser init failed");
    defer parser.deinit();

    var pipeline = pipeline_mod.Pipeline.init(arena_allocator, 1, false);
    defer pipeline.deinit();
    pipeline.addStageByName("basic_stats") catch return allocError(allocator, "Stage init failed");
    pipeline.addStageByName("per_base_quality") catch return allocError(allocator, "Stage init failed");
    // Add other relevant QC stages as needed...

    const record_buffer = arena_allocator.alloc(u8, 65536) catch return allocError(allocator, "Buffer alloc failed");

    while (parser.next(record_buffer) catch return allocError(allocator, "Parsing error")) |read| {
        pipeline.run(read) catch return allocError(allocator, "Pipeline run error");
    }

    pipeline.finalize() catch return allocError(allocator, "Pipeline finalize error");

    // Write report to an in-memory buffer
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    if (pipeline.scheduler) |*s| {
        structured_output.writeJsonReport(s, buffer.writer().any()) catch return allocError(allocator, "JSON report failed");
    }

    return allocator.dupeZ(u8, buffer.items) catch return allocError(allocator, "Final string alloc failed");
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
    const reader = buffered_reader.reader().any();

    var bam_reader = bam_reader_mod.BamReader.init(arena_allocator, reader) catch return allocError(allocator, "BAM reader init failed");
    defer bam_reader.deinit();

    var bam_pipeline = bam_pipeline_mod.BamPipeline.init(arena_allocator);
    defer bam_pipeline.deinit();
    bam_pipeline.addDefaultStages() catch return allocError(allocator, "Stage init failed");

    const record_buffer = arena_allocator.alloc(u8, 65536) catch return allocError(allocator, "Buffer alloc failed");
    while (bam_reader.next(record_buffer) catch return allocError(allocator, "BAM parsing error")) |record| {
        bam_pipeline.run(record) catch return allocError(allocator, "Pipeline run error");
    }
    
    bam_pipeline.finalize() catch return allocError(allocator, "Pipeline finalize error");
    
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    structured_output.writeJsonReport(bam_pipeline.scheduler, buffer.writer().any()) catch return allocError(allocator, "JSON report failed");
    
    return allocator.dupeZ(u8, buffer.items) catch return allocError(allocator, "Final string alloc failed");
}

pub export fn qwd_pipeline(config_json: [*:0]const u8, input_path: [*:0]const u8) [*:0]const u8 {
    _ = config_json;
    _ = input_path;
    return allocError(std.heap.c_allocator, "Pipeline from config not yet implemented in C ABI");
}

pub export fn qwd_free_string(ptr: [*:0]u8) void {
    const allocator = std.heap.c_allocator;
    // Don't free the static string literal used in a critical memory failure.
    if (std.mem.eql(u8, std.mem.span(ptr), "{\"error\":\"critical memory failure\"}")) {
        return;
    }
    allocator.free(std.mem.span(ptr));
}
