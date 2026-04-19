const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const PerbasequalityStage = struct {
    quality_counts: [1000][41]usize = [_][41]usize{[_]usize{0} ** 41} ** 1000,
    max_pos: usize = 0,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.qual.len;
        if (len > self.max_pos) self.max_pos = len;
        for (read.qual, 0..) |q, i| {
            if (i >= 1000) break;
            const phred = @min(@as(usize, q - 33), 40);
            self.quality_counts[i][phred] += 1;
        }
        return true; 
    }
    pub fn processBitplanes(ptr: *anyopaque, _: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        const max_len = @min(block.max_read_len, 1000);
        if (max_len > self.max_pos) self.max_pos = max_len;

        for (0..max_len) |pos| {
            const qual_col = block.qualities[pos];
            for (0..read_count) |i| {
                const q = qual_col[i];
                if (q == 0) continue;
                const phred = @min(@as(usize, q - 33), 40);
                self.quality_counts[pos][phred] += 1;
            }
        }
        return true;
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"quality_dist\": {{\"max_pos\": {d}, \"data\": [", .{self.max_pos});
        const limit = @min(self.max_pos, 1000);
        for (0..limit) |i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("[");
            for (self.quality_counts[i], 0..) |count, phred| {
                if (phred > 0) try writer.writeAll(",");
                try writer.print("{d}", .{count});
            }
            try writer.writeAll("]");
        }
        try writer.writeAll("]}");
    }
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        if (other.max_pos > self.max_pos) self.max_pos = other.max_pos;
        for (0..1000) |i| {
            for (0..41) |j| {
                self.quality_counts[i][j] += other.quality_counts[i][j];
            }
        }
    }
    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(PerbasequalityStage);
        new_self.* = self.*;
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = PerbasequalityStage.process,
    .finalize = PerbasequalityStage.finalize,
    .report = PerbasequalityStage.report,
    .reportJson = PerbasequalityStage.reportJson,
    .merge = PerbasequalityStage.merge,
    .clone = PerbasequalityStage.clone,
    .processBitplanes = PerbasequalityStage.processBitplanes,
};
