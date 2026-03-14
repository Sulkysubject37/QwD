const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const GcDistributionStage = struct {
    // bins: 0-10, 10-20, ..., 90-100 (10 bins)
    histogram: [10]usize = [_]usize{0} ** 10,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        if (len == 0) return true;

        var gc_count: usize = 0;
        for (read.seq) |base| {
            if (base == 'G' or base == 'C' or base == 'g' or base == 'c') {
                gc_count += 1;
            }
        }

        const gc_ratio = @as(f64, @floatFromInt(gc_count)) / @as(f64, @floatFromInt(len));
        var bin = @as(usize, @intFromFloat(gc_ratio * 10.0));
        if (bin == 10) bin = 9; // handle 100%

        self.histogram[bin] += 1;

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..10) |i| {
            self.histogram[i] += other.histogram[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("GC Distribution Report:\n", .{}) catch {};
        for (0..10) |i| {
            writer.print("  {d}0-{d}0%: {d}\n", .{ i, i + 1, self.histogram[i] }) catch {};
        }
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
