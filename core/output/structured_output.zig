const std = @import("std");
const scheduler_mod = @import("scheduler");

pub const OutputFormat = enum {
    text,
    json,
    ndjson,
};

pub fn writeJsonReport(scheduler: anytype, writer: std.io.AnyWriter) !void {
    const T = @TypeOf(scheduler);
    const ChildT = switch (@typeInfo(T)) {
        .Pointer => |ptr_info| ptr_info.child,
        else => T,
    };
    
    try writer.writeAll("{");
    try writer.writeAll("\"version\": \"1.1.0\",");
    
    var count: usize = 0;
    if (comptime @hasField(ChildT, "read_count")) {
        count = if (@TypeOf(scheduler.read_count) == std.atomic.Value(usize)) 
            scheduler.read_count.load(.monotonic) 
        else 
            scheduler.read_count;
        try writer.print("\"read_count\": {d},", .{count});
    } else if (comptime @hasField(ChildT, "record_count")) {
        count = scheduler.record_count;
        try writer.print("\"record_count\": {d},", .{count});
    }
    
    try writer.writeAll("\"stages\": {");
    
    var first = true;
    if (comptime @hasField(ChildT, "master_stages")) {
        for (scheduler.master_stages.items) |stage| {
            if (!first) try writer.writeAll(",");
            try stage.reportJson(writer);
            first = false;
        }
    } else if (comptime @hasField(ChildT, "stages")) {
        for (scheduler.stages.items) |stage| {
            if (!first) try writer.writeAll(",");
            try stage.reportJson(writer);
            first = false;
        }
    }
    
    try writer.writeAll("}");
    try writer.writeAll("}");
}

pub fn writeNdjsonReport(scheduler: anytype, writer: std.io.AnyWriter) !void {
    const T = @TypeOf(scheduler);
    const ChildT = switch (@typeInfo(T)) {
        .Pointer => |ptr_info| ptr_info.child,
        else => T,
    };

    try writer.writeAll("{\"type\": \"header\", \"version\": \"1.1.0\", ");
    var count: usize = 0;
    if (comptime @hasField(ChildT, "read_count")) {
        count = if (@TypeOf(scheduler.read_count) == std.atomic.Value(usize)) 
            scheduler.read_count.load(.monotonic) 
        else 
            scheduler.read_count;
        try writer.print("\"read_count\": {d}", .{count});
    } else if (comptime @hasField(ChildT, "record_count")) {
        count = scheduler.record_count;
        try writer.print("\"record_count\": {d}", .{count});
    }
    try writer.writeAll("}\n");

    if (comptime @hasField(ChildT, "master_stages")) {
        for (scheduler.master_stages.items) |stage| {
            try writer.writeAll("{");
            try stage.reportJson(writer);
            try writer.writeAll("}\n");
        }
    } else if (comptime @hasField(ChildT, "stages")) {
        for (scheduler.stages.items) |stage| {
            try writer.writeAll("{");
            try stage.reportJson(writer);
            try writer.writeAll("}\n");
        }
    }
}

pub fn writeNdjsonProcess(read_count: usize, writer: std.io.AnyWriter) !void {
    try writer.print("{{\"reads_processed\": {d}}}\n", .{read_count});
}

pub fn writeJsonEscaped(writer: std.io.AnyWriter, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try writer.print("\\u{x:0>4}", .{c}),
            else => try writer.writeByte(c),
        }
    }
}
