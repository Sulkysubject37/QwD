const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");

pub const MapqDistributionStage = struct {
    // MAPQ values typically range from 0 to 60, but let's size to 256 for safety.
    histogram: [256]usize = [_]usize{0} ** 256,

    pub fn process(ptr: *anyopaque, record: *bam_reader.AlignmentRecord) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if ((record.flag & 4) == 0) { // If mapped
            self.histogram[record.mapping_quality] += 1;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("MAPQ Distribution Report:\n", .{});
        for (0..61) |i| {
            if (self.histogram[i] > 0) {
                std.debug.print("  MAPQ {d}: {d}\n", .{ i, self.histogram[i] });
            }
        }
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
