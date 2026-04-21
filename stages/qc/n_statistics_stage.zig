const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const NStatisticsStage = struct {
    n_count: usize = 0,
    total_bases: usize = 0,

    pub fn init() NStatisticsStage { return .{}; }
    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (read.seq) |base| {
            self.total_bases += 1;
            if (base == 'N' or base == 'n') self.n_count += 1;
        }
        return true; 
    }
    pub fn processBitplanes(ptr: *anyopaque, bps: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const fused = @constCast(bps).getFused(block.read_count);
        self.n_count += fused.n_count;
        self.total_bases += fused.total_bases;
        return true;
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const ratio = if (self.total_bases > 0) @as(f64, @floatFromInt(self.n_count)) / @as(f64, @floatFromInt(self.total_bases)) else 0.0;
        try writer.print("\"n_statistics\": {{\"n_count\": {d}, \"n_ratio\": {d:.4}}}", .{self.n_count, ratio});
    }
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.n_count += other.n_count;
        self.total_bases += other.total_bases;
    }
    pub fn clone(_: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const new_self = try allocator.create(NStatisticsStage);
        new_self.* = .{};
        return new_self;
    }
    pub fn stage(self: *NStatisticsStage) stage_mod.Stage { return .{ .ptr = self, .vtable = &VTABLE }; }
};
const VTABLE = stage_mod.Stage.VTable{
    .process = NStatisticsStage.process, .finalize = NStatisticsStage.finalize,
    .report = NStatisticsStage.report, .reportJson = NStatisticsStage.reportJson,
    .merge = NStatisticsStage.merge, .clone = NStatisticsStage.clone,
    .processBitplanes = NStatisticsStage.processBitplanes,
};
