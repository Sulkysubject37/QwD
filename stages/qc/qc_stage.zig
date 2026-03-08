const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("../../core/stage/stage.zig");

pub const QcStage = struct {
    total_reads: usize = 0,
    total_bases: usize = 0,
    sum_quality: u64 = 0,
    mean_quality: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: parser.Read) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        self.total_bases += read.seq.len;
        for (read.qual) |q| {
            // phred = ascii_value - 33
            self.sum_quality += (q - 33);
        }
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_bases > 0) {
            self.mean_quality = @as(f64, @floatFromInt(self.sum_quality)) / @as(f64, @floatFromInt(self.total_bases));
        }
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("QC Report:\n", .{});
        std.debug.print("  Total reads: {d}\n", .{self.total_reads});
        std.debug.print("  Total bases: {d}\n", .{self.total_bases});
        std.debug.print("  Mean quality: {d:.2}\n", .{self.mean_quality});
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
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
