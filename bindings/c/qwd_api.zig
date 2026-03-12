const std = @import("std");
const pipeline_mod = @import("pipeline");
const parser_mod = @import("parser");

// Expose stable C-compatible functions
// These will be compiled into a shared library.

pub export fn qwd_fastq_qc(path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    const file_path = std.mem.span(path);
    
    // We'll return a simple JSON for now to establish the ABI
    const result = std.fmt.allocPrintZ(allocator, "{{\"status\": \"processed\", \"file\": \"{s}\"}}", .{file_path}) catch "{\"error\": \"out of memory\"}";
    return result;
}

pub export fn qwd_bam_stats(path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    const file_path = std.mem.span(path);
    const result = std.fmt.allocPrintZ(allocator, "{{\"status\": \"processed\", \"file\": \"{s}\"}}", .{file_path}) catch "{\"error\": \"out of memory\"}";
    return result;
}

pub export fn qwd_pipeline(config_json: [*:0]const u8, input_path: [*:0]const u8) [*:0]const u8 {
    const allocator = std.heap.c_allocator;
    _ = config_json;
    _ = input_path;
    const result = std.fmt.allocPrintZ(allocator, "{{\"status\": \"pipeline executed\"}}", .{}) catch "{\"error\": \"out of memory\"}";
    return result;
}

pub export fn qwd_free_string(ptr: [*:0]u8) void {
    const allocator = std.heap.c_allocator;
    allocator.free(std.mem.span(ptr));
}
