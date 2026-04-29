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

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        if (read_count == 0) return true;

        var fused: bitplanes_mod.BitplaneCore.FusedResults = .{};
        bp.computeFusedInto(read_count, &fused);
        
        self.total_reads += read_count;
        self.total_bases += fused.total_bases;
        self.integrity_violations += fused.integrity_violations;

        for (0..read_count) |i| {
            const len = block.read_lengths[i];
            if (len < self.min_length) self.min_length = len;
            if (len > self.max_length) self.max_length = len;
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    
    pub fn reportJson(ptr: *anyopaque, writer_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        // We cast to anytype via a generic wrapper if we want, or just assume std.debug for CLI
        // BUT to be safe we use a generic print approach or just cast to std.Io.Writer for Native.
        const writer: *std.Io.Writer = @ptrCast(@alignCast(writer_ptr));
        
        const mean = if (self.total_reads > 0) @as(f64, @floatFromInt(self.total_bases)) / @as(f64, @floatFromInt(self.total_reads)) else 0;
        const min_l = if (self.min_length == std.math.maxInt(usize)) @as(usize, 0) else self.min_length;
        try writer.print("\"basic_stats\": {{\"total_reads\": {d}, \"total_bases\": {d}, \"min_length\": {d}, \"max_length\": {d}, \"mean_length\": {d:.2}, \"integrity_violations\": {d}}}", .{
            self.total_reads, self.total_bases, min_l, self.max_length, mean, self.integrity_violations,
        });
    }

    pub fn stage(self: *BasicStatsStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *BasicStatsStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .basic_stats, &.{
            .processBitplanes = BasicStatsStage.processBitplanes,
            .finalize = BasicStatsStage.finalize,
            .reportJson = BasicStatsStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
