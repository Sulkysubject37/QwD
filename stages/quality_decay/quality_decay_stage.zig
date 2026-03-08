const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const QualityDecayStage = struct {
    const MAX_POS = 10000;
    quality_sum: [MAX_POS]u64 = [_]u64{0} ** MAX_POS,
    base_count: [MAX_POS]u64 = [_]u64{0} ** MAX_POS,
    mean_quality: [MAX_POS]f64 = [_]f64{0.0} ** MAX_POS,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const limit = if (read.qual.len > MAX_POS) MAX_POS else read.qual.len;

        for (0..limit) |pos| {
            const phred = read.qual[pos] - 33;
            self.quality_sum[pos] += phred;
            self.base_count[pos] += 1;
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (0..MAX_POS) |pos| {
            if (self.base_count[pos] > 0) {
                self.mean_quality[pos] = @as(f64, @floatFromInt(self.quality_sum[pos])) / @as(f64, @floatFromInt(self.base_count[pos]));
            }
        }
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("Quality Decay Report (first 10 positions):\n", .{});
        const limit = if (MAX_POS > 10) 10 else MAX_POS;
        for (0..limit) |pos| {
            if (self.base_count[pos] > 0) {
                std.debug.print("  Pos {d}: {d:.2}\n", .{ pos, self.mean_quality[pos] });
            }
        }
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
