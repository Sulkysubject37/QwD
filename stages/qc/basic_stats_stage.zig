const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const bitplanes_mod = @import("bitplanes");

pub const BasicStatsStage = struct {
    total_reads: usize = 0,
    total_bases: usize = 0,
    min_length: usize = std.math.maxInt(usize),
    max_length: usize = 0,
    integrity_violations: usize = 0,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        self.total_reads += 1;
        self.total_bases += len;
        if (len < self.min_length) self.min_length = len;
        if (len > self.max_length) self.max_length = len;
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        if (read_count == 0) return true;

        // Use computeFused to satisfy const constraints
        const fused = bp.computeFused(read_count);
        self.total_reads += read_count;
        self.total_bases += fused.total_bases;
        self.integrity_violations += fused.integrity_violations;

        // Correct lengths from the block's truth array
        for (0..read_count) |i| {
            const len = block.read_lengths[i];
            if (len < self.min_length) self.min_length = len;
            if (len > self.max_length) self.max_length = len;
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    
    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const mean = if (self.total_reads > 0) @as(f64, @floatFromInt(self.total_bases)) / @as(f64, @floatFromInt(self.total_reads)) else 0;
        writer.print("Reads: {d}, Bases: {d}, Mean: {d:.2}, Range: {d}-{d}\n", .{
            self.total_reads, self.total_bases, mean, self.min_length, self.max_length,
        }) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const mean = if (self.total_reads > 0) @as(f64, @floatFromInt(self.total_bases)) / @as(f64, @floatFromInt(self.total_reads)) else 0;
        const min_l = if (self.min_length == std.math.maxInt(usize)) @as(usize, 0) else self.min_length;
        try writer.print("\"basic_stats\": {{\"total_reads\": {d}, \"total_bases\": {d}, \"min_length\": {d}, \"max_length\": {d}, \"mean_length\": {d:.2}, \"integrity_violations\": {d}}}", .{
            self.total_reads, self.total_bases, min_l, self.max_length, mean, self.integrity_violations,
        });
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.total_bases += other.total_bases;
        if (other.min_length < self.min_length) self.min_length = other.min_length;
        if (other.max_length > self.max_length) self.max_length = other.max_length;
        self.integrity_violations += other.integrity_violations;
    }

    pub fn clone(_: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const new_self = try allocator.create(BasicStatsStage);
        new_self.* = .{};
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = BasicStatsStage.process,
    .finalize = BasicStatsStage.finalize,
    .report = BasicStatsStage.report,
    .reportJson = BasicStatsStage.reportJson,
    .merge = BasicStatsStage.merge,
    .clone = BasicStatsStage.clone,
    .processBitplanes = BasicStatsStage.processBitplanes,
};
