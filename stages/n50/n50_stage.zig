const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const N50Stage = struct {
    total_bases: u64 = 0,
    length_histogram: [30000]u32 = [_]u32{0} ** 30000,
    n50: usize = 0,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        self.total_bases += len;
        
        // Cap length at 29,999 to fit in histogram
        const idx = if (len >= 30000) 29999 else len;
        self.length_histogram[idx] += 1;

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_bases == 0) return;

        const target = self.total_bases / 2;
        var cumulative_bases: u64 = 0;
        
        var i: usize = 29999;
        while (i > 0) : (i -= 1) {
            cumulative_bases += @as(u64, self.length_histogram[i]) * i;
            if (cumulative_bases >= target) {
                self.n50 = i;
                break;
            }
        }
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("N50 Report:\n", .{});
        std.debug.print("  Total bases: {d}\n", .{self.total_bases});
        std.debug.print("  N50:         {d}\n", .{self.n50});
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
