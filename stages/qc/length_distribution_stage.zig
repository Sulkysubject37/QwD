const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const LengthDistributionStage = struct {
    read_count_per_bin: [6]usize = [_]usize{0} ** 6,
    total_reads: usize = 0,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        self.total_reads += 1;

        if (len < 100) {
            self.read_count_per_bin[0] += 1;
        } else if (len < 500) {
            self.read_count_per_bin[1] += 1;
        } else if (len < 1000) {
            self.read_count_per_bin[2] += 1;
        } else if (len < 5000) {
            self.read_count_per_bin[3] += 1;
        } else if (len < 10000) {
            self.read_count_per_bin[4] += 1;
        } else {
            self.read_count_per_bin[5] += 1;
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("Read Length Distribution Report:\n", .{});
        std.debug.print("  0-100:     {d}\n", .{self.read_count_per_bin[0]});
        std.debug.print("  100-500:   {d}\n", .{self.read_count_per_bin[1]});
        std.debug.print("  500-1000:  {d}\n", .{self.read_count_per_bin[2]});
        std.debug.print("  1000-5000: {d}\n", .{self.read_count_per_bin[3]});
        std.debug.print("  5000-10000:{d}\n", .{self.read_count_per_bin[4]});
        std.debug.print("  10000+:    {d}\n", .{self.read_count_per_bin[5]});
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
