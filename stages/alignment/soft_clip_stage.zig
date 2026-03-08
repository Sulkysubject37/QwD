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

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("Soft Clipping Report:\n", .{});
        std.debug.print("  Soft-clipped reads: {d}\n", .{self.soft_clipped_reads});
        std.debug.print("  Soft-clipped bases: {d}\n", .{self.soft_clipped_bases});
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
