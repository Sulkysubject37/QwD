const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const BasicStatsStage = struct {
    total_reads: usize = 0,
    total_bases: usize = 0,
    min_read_length: usize = std.math.maxInt(usize),
    max_read_length: usize = 0,
    mean_read_length: f64 = 0.0,
    integrity_violations: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !*BasicStatsStage {
        const self = try allocator.create(BasicStatsStage);
        self.* = .{};
        return self;
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        self.total_reads += 1;
        self.total_bases += len;
        if (len < self.min_read_length) self.min_read_length = len;
        if (len > self.max_read_length) self.max_read_length = len;
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bps: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        // Use the fused result path for maximum speed
        const fused = @constCast(bps).getFused(block.read_count);
        self.total_reads += block.read_count;
        self.total_bases += fused.total_bases;
        self.integrity_violations += fused.integrity_violations;
        
        for (0..block.read_count) |i| {
            const len = block.read_lengths[i];
            if (len < self.min_read_length) self.min_read_length = len;
            if (len > self.max_read_length) self.max_read_length = len;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_reads > 0) {
            self.mean_read_length = @as(f64, @floatFromInt(self.total_bases)) / @as(f64, @floatFromInt(self.total_reads));
        } else {
            self.min_read_length = 0;
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.total_bases += other.total_bases;
        self.integrity_violations += other.integrity_violations;
        if (other.min_read_length < self.min_read_length) self.min_read_length = other.min_read_length;
        if (other.max_read_length > self.max_read_length) self.max_read_length = other.max_read_length;
    }

    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("\n[Basic Statistics]\n", .{}) catch {};
        writer.print("  Total reads: {d}\n", .{self.total_reads}) catch {};
        writer.print("  Total bases: {d}\n", .{self.total_bases}) catch {};
        writer.print("  Min length:  {d}\n", .{self.min_read_length}) catch {};
        writer.print("  Max length:  {d}\n", .{self.max_read_length}) catch {};
        writer.print("  Mean length: {d:.2}\n", .{self.mean_read_length}) catch {};
        writer.print("  Integrity Violations: {d}\n", .{self.integrity_violations}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"basic_stats\": {{\"total_reads\": {d}, \"total_bases\": {d}, \"min_length\": {d}, \"max_length\": {d}, \"mean_length\": {d:.2}, \"integrity_violations\": {d}}}", .{
            self.total_reads,
            self.total_bases,
            self.min_read_length,
            self.max_read_length,
            self.mean_read_length,
            self.integrity_violations,
        });
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(@This());
        new_self.* = self.*;
        return new_self;
    }

    pub fn stage(self: *BasicStatsStage) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &VTABLE,
        };
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
