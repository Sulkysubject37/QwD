const std = @import("std");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const QualitydistStage = struct {
    // Quality counts per position: [position][quality_score (0-93)]
    counts: [512][94]u64 = undefined,
    max_pos: usize = 0,

    pub fn init() QualitydistStage {
        var self = QualitydistStage{};
        @memset(std.mem.asBytes(&self.counts), 0);
        return self;
    }

    pub fn processBitplanes(ptr: *anyopaque, _: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        const active_max = block.active_max_len;
        if (active_max > self.max_pos) self.max_pos = active_max;

        for (0..active_max) |pos| {
            if (pos >= 512) break;
            const qual_col = block.qualities[pos];
            for (0..read_count) |read_idx| {
                if (pos < block.read_lengths[read_idx]) {
                    const q_char = qual_col[read_idx];
                    const q = @min(q_char -% 33, 93);
                    self.counts[pos][q] += 1;
                }
            }
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    
    pub fn reportJson(ptr: *anyopaque, writer_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const writer: *std.Io.Writer = @ptrCast(@alignCast(writer_ptr));
        
        try writer.print("\"quality_dist\": {{\"max_pos\": {d}, \"data\": [", .{self.max_pos});
        for (0..self.max_pos) |p| {
            if (p >= 512) break;
            if (p > 0) try writer.writeAll(",");
            try writer.writeAll("[");
            for (0..94) |q| {
                if (q > 0) try writer.writeAll(",");
                try writer.print("{d}", .{self.counts[p][q]});
            }
            try writer.writeAll("]");
        }
        try writer.writeAll("]}}");
    }

    pub fn stage(self: *QualitydistStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *QualitydistStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .quality_dist, &.{
            .processBitplanes = QualitydistStage.processBitplanes,
            .finalize = QualitydistStage.finalize,
            .reportJson = QualitydistStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
