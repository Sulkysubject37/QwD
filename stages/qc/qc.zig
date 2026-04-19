const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const QcStage = struct {
    pub fn process(_: *anyopaque, _: *const parser.Read) anyerror!bool { return true; }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(_: *anyopaque, writer: *std.Io.Writer) anyerror!void { try writer.writeAll("{}"); }
    pub fn merge(_: *anyopaque, _: *anyopaque) anyerror!void {}
    pub fn clone(_: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self = try allocator.create(QcStage);
        self.* = .{};
        return self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = QcStage.process,
    .finalize = QcStage.finalize,
    .report = QcStage.report,
    .reportJson = QcStage.reportJson,
    .merge = QcStage.merge,
    .clone = QcStage.clone,
};
