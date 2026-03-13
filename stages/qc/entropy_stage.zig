const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const entropy_lut_mod = @import("entropy_lut");

pub const EntropyStage = struct {
    total_reads: usize = 0,
    total_entropy_sum: f64 = 0.0,
    low_complexity_reads: usize = 0,
    mean_entropy: f64 = 0.0,
    
    // We will use the global LUT initialized once
    
    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        if (len == 0) return true;

        var base_counts = [_]usize{0} ** 4;
        for (read.seq) |base| {
            switch (base) {
                'A', 'a' => base_counts[0] += 1,
                'C', 'c' => base_counts[1] += 1,
                'G', 'g' => base_counts[2] += 1,
                'T', 't' => base_counts[3] += 1,
                else => {},
            }
        }

        const entropy = entropy_lut_mod.global_lut.getEntropy(base_counts, len);

        self.total_reads += 1;
        self.total_entropy_sum += entropy;

        if (entropy < 1.5) {
            self.low_complexity_reads += 1;
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_reads > 0) {
            self.mean_entropy = self.total_entropy_sum / @as(f64, @floatFromInt(self.total_reads));
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Sequence Entropy Report:\n", .{}) catch {};
        writer.print("  Mean entropy:      {d:.4}\n", .{self.mean_entropy}) catch {};
        writer.print("  Low complexity:    {d}\n", .{self.low_complexity_reads}) catch {};
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
