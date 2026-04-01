const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");
const cigar_parser = @import("cigar_parser");

pub const SoftClipStage = struct {
    soft_clipped_reads: usize = 0,
    soft_clipped_bases: usize = 0,

    pub fn process(ptr: *anyopaque, record: *bam_reader.AlignmentRecord) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if ((record.flag & 4) == 0) {
            const stats = cigar_parser.parseCigar(record.cigar);
            if (stats.soft_clips > 0) {
                self.soft_clipped_reads += 1;
                self.soft_clipped_bases += stats.soft_clips;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Soft Clipping Report:\n", .{}) catch {};
        writer.print("  Soft-clipped reads: {d}\n", .{self.soft_clipped_reads}) catch {};
        writer.print("  Soft-clipped bases: {d}\n", .{self.soft_clipped_bases}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"soft_clipping\": {{\"soft_clipped_reads\": {d}, \"soft_clipped_bases\": {d}}}", .{ self.soft_clipped_reads, self.soft_clipped_bases });
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
