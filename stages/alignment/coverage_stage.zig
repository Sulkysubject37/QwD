const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");
const cigar_parser = @import("cigar_parser");

pub const CoverageStage = struct {
    total_aligned_bases: u64 = 0,
    reference_length: u64 = 3000000000, // Dummy length for now
    coverage_estimate: f64 = 0.0,

    pub fn init(ref_len: u64) CoverageStage {
        return CoverageStage{
            .reference_length = ref_len,
        };
    }

    pub fn process(ptr: *anyopaque, record: *bam_reader.AlignmentRecord) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if ((record.flag & 4) == 0) {
            const stats = cigar_parser.parseCigar(record.cigar);
            self.total_aligned_bases += stats.aligned_length;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.reference_length > 0) {
            self.coverage_estimate = @as(f64, @floatFromInt(self.total_aligned_bases)) / @as(f64, @floatFromInt(self.reference_length));
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Coverage Report:\n", .{}) catch {};
        writer.print("  Aligned bases:     {d}\n", .{self.total_aligned_bases}) catch {};
        writer.print("  Est. Coverage:     {d:.2}x\n", .{self.coverage_estimate}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print(
            \\"coverage": {{
            \\  "aligned_bases": {d},
            \\  "reference_length": {d},
            \\  "coverage_estimate": {d:.2}
            \\}}
        , .{
            self.total_aligned_bases,
            self.reference_length,
            self.coverage_estimate,
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
