const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const NStatisticsStage = struct {
    total_bases: u64 = 0,
    length_histogram: [30000]u32 = [_]u32{0} ** 30000,
    n10: usize = 0,
    n25: usize = 0,
    n50: usize = 0,
    n75: usize = 0,
    n90: usize = 0,

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

        const t10 = self.total_bases / 10;
        const t25 = self.total_bases / 4;
        const t50 = self.total_bases / 2;
        const t75 = (self.total_bases * 3) / 4;
        const t90 = (self.total_bases * 9) / 10;
        
        var cumulative_bases: u64 = 0;
        
        var i: usize = 29999;
        while (i > 0) : (i -= 1) {
            cumulative_bases += @as(u64, self.length_histogram[i]) * i;
            if (self.n10 == 0 and cumulative_bases >= t10) self.n10 = i;
            if (self.n25 == 0 and cumulative_bases >= t25) self.n25 = i;
            if (self.n50 == 0 and cumulative_bases >= t50) self.n50 = i;
            if (self.n75 == 0 and cumulative_bases >= t75) self.n75 = i;
            if (self.n90 == 0 and cumulative_bases >= t90) self.n90 = i;
            
            if (self.n90 != 0) break;
        }
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("N-Statistics Report:\n", .{});
        std.debug.print("  N10: {d}\n", .{self.n10});
        std.debug.print("  N25: {d}\n", .{self.n25});
        std.debug.print("  N50: {d}\n", .{self.n50});
        std.debug.print("  N75: {d}\n", .{self.n75});
        std.debug.print("  N90: {d}\n", .{self.n90});
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
