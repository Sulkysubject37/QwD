const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");
const cigar_parser = @import("cigar_parser");

pub const ErrorRateStage = struct {
    mismatches: usize = 0,
    aligned_bases: usize = 0,
    error_rate: f64 = 0.0,

    pub fn process(ptr: *anyopaque, record: *bam_reader.AlignmentRecord) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if ((record.flag & 4) == 0) {
            const stats = cigar_parser.parseCigar(record.cigar);
            self.aligned_bases += stats.aligned_length;
            
            // For a real BAM, we would parse NM or MD tags.
            // Here, we simulate by assuming insertions/deletions are errors.
            self.mismatches += stats.insertions + stats.deletions;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.aligned_bases > 0) {
            self.error_rate = @as(f64, @floatFromInt(self.mismatches)) / @as(f64, @floatFromInt(self.aligned_bases));
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Error Rate Report:\n", .{}) catch {};
        writer.print("  Aligned bases: {d}\n", .{self.aligned_bases}) catch {};
        writer.print("  Mismatches:    {d}\n", .{self.mismatches}) catch {};
        writer.print("  Error rate:    {d:.4}%\n", .{self.error_rate * 100.0}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"error_rate_stats\": {{\"aligned_bases\": {d}, \"mismatches\": {d}, \"error_rate\": {d:.6}}}", .{ self.aligned_bases, self.mismatches, self.error_rate });
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
