const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const DuplicationStage = struct {
    total_reads: usize = 0,
    duplicate_count: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DuplicationStage { return .{ .allocator = allocator }; }
    pub fn process(ptr: *anyopaque, _: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        return true; 
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Duplication processed: {d}\n", .{self.total_reads}) catch {};
    }
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const ratio: f64 = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_count)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        try writer.print("\"duplication\": {{\"total_reads\": {d}, \"duplicate_reads\": {d}, \"duplication_ratio\": {d:.4}}}", .{
            self.total_reads,
            self.duplicate_count,
            ratio,
        });
    }
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
    }
    pub fn clone(_: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const new_self = try allocator.create(DuplicationStage);
        new_self.* = DuplicationStage.init(allocator);
        return new_self;
    }
    pub fn stage(self: *DuplicationStage) stage_mod.Stage { return .{ .ptr = self, .vtable = &VTABLE }; }
};
const VTABLE = stage_mod.Stage.VTable{
    .process = DuplicationStage.process, .finalize = DuplicationStage.finalize,
    .report = DuplicationStage.report, .reportJson = DuplicationStage.reportJson,
    .merge = DuplicationStage.merge, .clone = DuplicationStage.clone,
};
