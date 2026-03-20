const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const FilterStage = struct {
    min_quality: f64,
    reads_seen: usize = 0,
    reads_passed: usize = 0,
    reads_filtered: usize = 0,

    pub fn init(min_quality: f64) FilterStage {
        return FilterStage{
            .min_quality = min_quality,
        };
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.reads_seen += 1;

        var sum: u64 = 0;
        for (read.qual) |q| {
            const phred = if (q >= 33) q - 33 else 0;
            sum += phred;
        }

        const avg = if (read.qual.len > 0) @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(read.qual.len)) else 0.0;

        if (avg >= self.min_quality) {
            self.reads_passed += 1;
            return true;
        } else {
            self.reads_filtered += 1;
            return false;
        }
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Filter Report (min_qual={d:.2}):\n", .{self.min_quality}) catch {};
        writer.print("  Reads seen:     {d}\n", .{self.reads_seen}) catch {};
        writer.print("  Reads passed:   {d}\n", .{self.reads_passed}) catch {};
        writer.print("  Reads filtered: {d}\n", .{self.reads_filtered}) catch {};
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
