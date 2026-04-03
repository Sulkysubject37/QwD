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

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("MAPQ Distribution Report:\n", .{}) catch {};
        for (0..61) |i| {
            if (self.histogram[i] > 0) {
                writer.print("  MAPQ {d}: {d}\n", .{ i, self.histogram[i] }) catch {};
            }
        }
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"mapq_distribution\": {\"histogram\": [");
        for (0..61) |i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{self.histogram[i]});
        }
        try writer.writeAll("]}");
    }

    const VTABLE = bam_stage.BamStage.VTable{
        .process = process,
        .finalize = finalize,
        .report = report,
        .reportJson = reportJson,
    };

    pub fn stage(self: *@This()) bam_stage.BamStage {
        return .{
            .ptr = self,
            .vtable = &VTABLE,
        };
    }
};
