const std = @import("std");
const scheduler_mod = @import("scheduler");

pub const OutputFormat = enum {
    text,
    json,
    ndjson,
};

pub fn writeJsonReport(scheduler: anytype, writer: std.io.AnyWriter) !void {
    try writer.writeAll("{");
    
    // Handle read_count or record_count
    if (@hasField(@TypeOf(scheduler), "read_count")) {
        const count = if (@TypeOf(scheduler.read_count) == std.atomic.Value(usize)) 
            scheduler.read_count.load(.monotonic) 
        else 
            scheduler.read_count;
        try writer.print("\"read_count\": {d}", .{count});
    } else if (@hasField(@TypeOf(scheduler), "record_count")) {
        try writer.print("\"record_count\": {d}", .{scheduler.record_count});
    }
    
    try writer.writeAll("}");
}

pub fn writeNdjsonProcess(read_count: usize, writer: std.io.AnyWriter) !void {
    try writer.print("{{\"reads_processed\": {d}}}\n", .{read_count});
}
