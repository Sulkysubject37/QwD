const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const KmerSpectrumStage = struct {
    k: usize = 11,
    pub fn init(allocator: std.mem.Allocator, k: usize) KmerSpectrumStage {
        _ = allocator;
        return .{ .k = k };
    }
    pub fn process(_: *anyopaque, _: *const parser.Read) anyerror!bool { return true; }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"kmer_spectrum\": {{\"k\": {d}, \"counts\": [0,0,0]}}", .{self.k}); 
    }
    pub fn merge(_: *anyopaque, _: *anyopaque) anyerror!void {}
    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(KmerSpectrumStage);
        new_self.* = self.*;
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = KmerSpectrumStage.process,
    .finalize = KmerSpectrumStage.finalize,
    .report = KmerSpectrumStage.report,
    .reportJson = KmerSpectrumStage.reportJson,
    .merge = KmerSpectrumStage.merge,
    .clone = KmerSpectrumStage.clone,
};
