const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const OverrepresentedStage = struct {
    pub fn init(allocator: std.mem.Allocator) OverrepresentedStage {
        _ = allocator;
        return .{};
    }
    pub fn process(_: *anyopaque, _: *const parser.Read) anyerror!bool { return true; }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(_: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        try writer.writeAll("\"overrepresented\": {\"unique_sequences\": 0, \"most_frequent\": \"None\", \"most_frequent_count\": 0}"); 
    }
    pub fn merge(_: *anyopaque, _: *anyopaque) anyerror!void {}
    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(OverrepresentedStage);
        new_self.* = self.*;
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = OverrepresentedStage.process,
    .finalize = OverrepresentedStage.finalize,
    .report = OverrepresentedStage.report,
    .reportJson = OverrepresentedStage.reportJson,
    .merge = OverrepresentedStage.merge,
    .clone = OverrepresentedStage.clone,
};
