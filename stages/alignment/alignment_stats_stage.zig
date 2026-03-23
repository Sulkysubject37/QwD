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

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Alignment Statistics:\n", .{}) catch {};
        writer.print("  Total alignments: {d}\n", .{self.total_alignments}) catch {};
        writer.print("  Mapped reads:     {d}\n", .{self.mapped_reads}) catch {};
        writer.print("  Unmapped reads:   {d}\n", .{self.unmapped_reads}) catch {};
        writer.print("  Mean MAPQ:        {d:.2}\n", .{self.mean_mapping_quality}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print(
            \\"alignment_stats": {{
            \\  "total_records": {d},
            \\  "mapped_reads": {d},
            \\  "unmapped_reads": {d},
            \\  "mean_mapq": {d:.2}
            \\}}
        , .{
            self.total_alignments,
            self.mapped_reads,
            self.unmapped_reads,
            self.mean_mapping_quality,
        });
    }

    pub fn stage(self: *@This()) bam_stage.BamStage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
                .reportJson = reportJson,
            },
        };
    }
};
