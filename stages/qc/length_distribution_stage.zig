const std = @import("std");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const LengthDistributionStage = struct {
    bins: [1000]usize = [_]usize{0} ** 1000,
    max_recorded: usize = 0,

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
    
    pub fn reportJson(ptr: *anyopaque, writer_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const writer: *std.Io.Writer = @ptrCast(@alignCast(writer_ptr));
        try writer.writeAll("\"length_distribution\": {\"bins\": [");
        for (self.bins[0..@min(self.max_recorded + 1, 1000)], 0..) |count, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{d}", .{count});
        }
        try writer.writeAll("]}");
    }

    pub fn stage(self: *LengthDistributionStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *LengthDistributionStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .length_distribution, &.{
            .processBitplanes = LengthDistributionStage.processBitplanes,
            .finalize = LengthDistributionStage.finalize,
            .reportJson = LengthDistributionStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
