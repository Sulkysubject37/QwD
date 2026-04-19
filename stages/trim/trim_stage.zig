const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const TrimStage = struct {
    reads_seen: usize = 0,
    adapter_sequence: ?[]const u8 = null,
    trim_front: usize = 0,
    trim_tail: usize = 0,

    pub fn init(adapter: ?[]const u8, front: usize, tail: usize) TrimStage {
        return .{ .adapter_sequence = adapter, .trim_front = front, .trim_tail = tail };
    }
    pub fn process(ptr: *anyopaque, _: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.reads_seen += 1;
        return true; 
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Trim processed: {d}\n", .{self.reads_seen}) catch {};
    }
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"trim\": {{\"reads_seen\": {d}, \"reads_trimmed\": {d}}}", .{
            self.reads_seen,
            self.reads_seen, // Currently all reads are 'seen' by the trim stage, we stub trimmed for now
        });
    }
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.reads_seen += other.reads_seen;
    }
    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(TrimStage);
        new_self.* = self.*;
        return new_self;
    }
    pub fn stage(self: *TrimStage) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};
const VTABLE = stage_mod.Stage.VTable{
    .process = TrimStage.process,
    .finalize = TrimStage.finalize,
    .report = TrimStage.report,
    .reportJson = TrimStage.reportJson,
    .merge = TrimStage.merge,
    .clone = TrimStage.clone,
};
