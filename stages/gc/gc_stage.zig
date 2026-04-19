const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const GcStage = struct {
    gc_count: usize = 0,
    total_count: usize = 0,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (read.seq) |b| {
            self.total_count += 1;
            if (b == 'G' or b == 'C' or b == 'g' or b == 'c') self.gc_count += 1;
        }
        return true; 
    }
    pub fn processBitplanes(ptr: *anyopaque, bps: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const fused = @constCast(bps).getFused(block.read_count);
        self.gc_count += fused.gc_count;
        self.total_count += fused.total_bases;
        return true;
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const ratio = if (self.total_count > 0) @as(f64, @floatFromInt(self.gc_count)) / @as(f64, @floatFromInt(self.total_count)) else 0.0;
        try writer.print("\"gc_content\": {{\"ratio\": {d:.4}}}", .{ratio});
    }
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.gc_count += other.gc_count;
        self.total_count += other.total_count;
    }
    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(GcStage);
        new_self.* = self.*;
        return new_self;
    }
    pub fn stage(self: *GcStage) stage_mod.Stage { return .{ .ptr = self, .vtable = &VTABLE }; }
};
const VTABLE = stage_mod.Stage.VTable{
    .process = GcStage.process, .finalize = GcStage.finalize,
    .report = GcStage.report, .reportJson = GcStage.reportJson,
    .merge = GcStage.merge, .clone = GcStage.clone,
    .processBitplanes = GcStage.processBitplanes,
};
