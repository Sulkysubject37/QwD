const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const TaxedStage = struct {
    pub fn init(allocator: std.mem.Allocator) !TaxedStage {
        _ = allocator;
        return .{};
    }
    pub fn process(_: *anyopaque, _: *const parser.Read) anyerror!bool { return true; }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(_: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        try writer.writeAll("\"taxonomic_screening\": [{\"taxon\": \"Unknown\", \"count\": 0}]"); 
    }
    pub fn merge(_: *anyopaque, _: *anyopaque) anyerror!void {}
    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(TaxedStage);
        new_self.* = self.*;
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = TaxedStage.process,
    .finalize = TaxedStage.finalize,
    .report = TaxedStage.report,
    .reportJson = TaxedStage.reportJson,
    .merge = TaxedStage.merge,
    .clone = TaxedStage.clone,
};
