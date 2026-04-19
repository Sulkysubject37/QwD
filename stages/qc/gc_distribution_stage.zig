const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const GcdistributionStage = struct {
    bins: [101]usize = [_]usize{0} ** 101,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (read.seq.len == 0) return true;
        var gc: usize = 0;
        for (read.seq) |b| {
            switch (b) {
                'G', 'g', 'C', 'c' => gc += 1,
                else => {},
            }
        }
        const gc_perc = (gc * 100) / read.seq.len;
        self.bins[gc_perc] += 1;
        return true; 
    }
    pub fn processBitplanes(ptr: *anyopaque, _: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (0..block.read_count) |i| {
            const len = block.read_lengths[i];
            if (len == 0) continue;
            var gc: usize = 0;
            for (0..len) |pos| {
                const b = block.bases[pos][i];
                switch (b) {
                    'G', 'g', 'C', 'c' => gc += 1,
                    else => {},
                }
            }
            const gc_perc = (gc * 100) / len;
            self.bins[gc_perc] += 1;
        }
        return true;
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"gc_distribution\": {\"bins\": [");
        for (self.bins, 0..) |count, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{d}", .{count});
        }
        try writer.writeAll("]}");
    }
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..101) |i| {
            self.bins[i] += other.bins[i];
        }
    }
    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(GcdistributionStage);
        new_self.* = self.*;
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = GcdistributionStage.process,
    .finalize = GcdistributionStage.finalize,
    .report = GcdistributionStage.report,
    .reportJson = GcdistributionStage.reportJson,
    .merge = GcdistributionStage.merge,
    .clone = GcdistributionStage.clone,
    .processBitplanes = GcdistributionStage.processBitplanes,
};
