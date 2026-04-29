const std = @import("std");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const bitplanes_mod = @import("bitplanes");

pub const GcdistributionStage = struct {
    gc_counts: [101]u64 = [_]u64{0} ** 101,
    total_reads: usize = 0,

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        if (read_count == 0) return true;

        var fused: bitplanes_mod.BitplaneCore.FusedResults = .{};
        bp.computeFusedInto(read_count, &fused);

        for (0..read_count) |i| {
            const len = block.read_lengths[i];
            if (len == 0) continue;
            const gc_count = fused.per_read_gc[i];
            const gc_perc = @as(f32, @floatFromInt(gc_count)) / @as(f32, @floatFromInt(len)) * 100.0;
            const bin = @as(usize, @intFromFloat(@min(100.0, gc_perc)));
            self.gc_counts[bin] += 1;
        }
        self.total_reads += read_count;
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    
    pub fn reportJson(ptr: *anyopaque, writer_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const writer: *std.Io.Writer = @ptrCast(@alignCast(writer_ptr));
        try writer.print("\"gc_distribution\": {{\"bins\": [", .{});
        for (self.gc_counts, 0..) |count, i| {
            try writer.print("{d}", .{count});
            if (i < 100) try writer.writeAll(", ");
        }
        try writer.writeAll("]}");
    }

    pub fn stage(self: *GcdistributionStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *GcdistributionStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .gc_distribution, &.{
            .processBitplanes = GcdistributionStage.processBitplanes,
            .finalize = GcdistributionStage.finalize,
            .reportJson = GcdistributionStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
