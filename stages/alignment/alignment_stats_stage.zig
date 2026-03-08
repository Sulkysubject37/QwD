const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");

pub const AlignmentStatsStage = struct {
    total_alignments: usize = 0,
    mapped_reads: usize = 0,
    unmapped_reads: usize = 0,
    sum_mapq: u64 = 0,
    mean_mapping_quality: f64 = 0.0,

    pub fn process(ptr: *anyopaque, record: *bam_reader.AlignmentRecord) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_alignments += 1;
        
        // Flag 4 means unmapped
        if ((record.flag & 4) != 0) {
            self.unmapped_reads += 1;
        } else {
            self.mapped_reads += 1;
            self.sum_mapq += record.mapping_quality;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.mapped_reads > 0) {
            self.mean_mapping_quality = @as(f64, @floatFromInt(self.sum_mapq)) / @as(f64, @floatFromInt(self.mapped_reads));
        }
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("Alignment Statistics:\n", .{});
        std.debug.print("  Total alignments: {d}\n", .{self.total_alignments});
        std.debug.print("  Mapped reads:     {d}\n", .{self.mapped_reads});
        std.debug.print("  Unmapped reads:   {d}\n", .{self.unmapped_reads});
        std.debug.print("  Mean MAPQ:        {d:.2}\n", .{self.mean_mapping_quality});
    }

    pub fn stage(self: *@This()) bam_stage.BamStage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
            },
        };
    }
};
