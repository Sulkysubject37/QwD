const std = @import("std");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const bitplanes_mod = @import("bitplanes");

pub const NStatisticsStage = struct {
    n_count: usize = 0,
    total_bases: usize = 0,

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        if (read_count == 0) return true;

        var fused: bitplanes_mod.BitplaneCore.FusedResults = .{};
        bp.computeFusedInto(read_count, &fused);
        
        self.n_count += fused.n_count;
        self.total_bases += fused.total_bases;
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    
    pub fn reportJson(ptr: *anyopaque, writer_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const writer: *std.Io.Writer = @ptrCast(@alignCast(writer_ptr));
        const ratio = if (self.total_bases > 0) @as(f64, @floatFromInt(self.n_count)) / @as(f64, @floatFromInt(self.total_bases)) else 0.0;
        try writer.print("\"n_statistics\": {{\"n_count\": {d}, \"n_ratio\": {d:.4}}}", .{self.n_count, ratio});
    }

    pub fn stage(self: *NStatisticsStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *NStatisticsStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .n_statistics, &.{
            .processBitplanes = NStatisticsStage.processBitplanes,
            .finalize = NStatisticsStage.finalize,
            .reportJson = NStatisticsStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
