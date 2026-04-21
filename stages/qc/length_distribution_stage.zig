const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const LengthDistributionStage = struct {
    bins: [1000]usize = [_]usize{0} ** 1000,
    max_recorded: usize = 0,

    pub fn init(_: std.mem.Allocator) LengthDistributionStage {
        return .{};
    }
    pub fn deinit(_: *LengthDistributionStage) void {}
    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        const bin_idx = @min(len, 999);
        self.bins[bin_idx] += 1;
        if (len > self.max_recorded) self.max_recorded = len;
        return true; 
    }
    pub fn processBitplanes(ptr: *anyopaque, _: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (0..block.read_count) |i| {
            const len = block.read_lengths[i];
            const bin_idx = @min(@as(usize, len), 999);
            self.bins[bin_idx] += 1;
            if (len > self.max_recorded) self.max_recorded = len;
        }
        return true;
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Max length: {d}\n", .{self.max_recorded}) catch {};
    }
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"length_distribution\": {\"bins\": [");
        for (self.bins[0..@min(self.max_recorded + 1, 1000)], 0..) |count, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{d}", .{count});
        }
        try writer.writeAll("]}");
    }
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..1000) |i| {
            self.bins[i] += other.bins[i];
        }
        if (other.max_recorded > self.max_recorded) self.max_recorded = other.max_recorded;
    }
    pub fn clone(_: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const new_self = try allocator.create(LengthDistributionStage);
        new_self.* = .{};
        return new_self;
    }
    pub fn stage(self: *LengthDistributionStage) stage_mod.Stage { return .{ .ptr = self, .vtable = &VTABLE }; }
};
const VTABLE = stage_mod.Stage.VTable{
    .process = LengthDistributionStage.process, .finalize = LengthDistributionStage.finalize,
    .report = LengthDistributionStage.report, .reportJson = LengthDistributionStage.reportJson,
    .merge = LengthDistributionStage.merge, .clone = LengthDistributionStage.clone,
    .processBitplanes = LengthDistributionStage.processBitplanes,
};
