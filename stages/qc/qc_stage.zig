const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const simd = @import("simd_ops");

pub const QcStage = struct {
    total_reads: usize = 0,
    total_bases: usize = 0,
    sum_quality: u64 = 0,
    mean_quality: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        self.total_bases += read.seq.len;
        
        if (simd.simd_enabled()) {
            self.sum_quality += simd.sumPhredSimd(read.qual);
        } else {
            for (read.qual) |q| {
                const phred = if (q >= 33) q - 33 else 0;
                self.sum_quality += phred;
            }
        }
        return true;
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
