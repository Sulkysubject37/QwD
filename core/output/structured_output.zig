const std = @import("std");
const scheduler_mod = @import("scheduler");

pub const OutputFormat = enum {
    text,
    json,
    ndjson,
};

pub fn writeNdjsonReport(scheduler: anytype, writer: std.Io.Writer) anyerror!void { const w = writer;
    const T = @TypeOf(scheduler);
    const ChildT = switch (@typeInfo(T)) {
        .Pointer => |ptr_info| ptr_info.child,
        else => T,
    };

    try w.writeAll("{\"type\": \"header\", \"version\": \"1.1.0\", ");
    var count: usize = 0;
    if (comptime @hasField(ChildT, "read_count")) {
        count = if (@TypeOf(scheduler.read_count) == std.atomic.Value(usize)) 
            scheduler.read_count.load(.monotonic) 
        else 
            scheduler.read_count;
        try w.print("\"read_count\": {d}", .{count});
    } else if (comptime @hasField(ChildT, "record_count")) {
        count = scheduler.record_count;
        try w.print("\"read_count\": {d}", .{count});
    }
    try w.writeAll("}\n");

    if (comptime @hasField(ChildT, "master_stages")) {
        for (scheduler.master_stages.items) |stage| {
            try w.writeAll("{");
            try stage.reportJson(w);
            try w.writeAll("}\n");
        }
    } else if (comptime @hasField(ChildT, "stages")) {
        for (scheduler.stages.items) |stage| {
            try w.writeAll("{");
            try stage.reportJson(w);
            try w.writeAll("}\n");
        }
    }
}

pub fn writeNdjsonProcess(read_count: usize, writer: std.Io.Writer) !void { const w = writer;
    try w.print("{{\"reads_processed\": {d}}}\n", .{read_count});
}

pub fn writeJsonEscaped(writer: std.Io.Writer, s: []const u8) !void { const w = writer;
    for (s) |c| {
        switch (c) {
            '\"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try w.print("\\u{x:0>4}", .{c}),
            else => try w.writeByte(c),
        }
    }
}
