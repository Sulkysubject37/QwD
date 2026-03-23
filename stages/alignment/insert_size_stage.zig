const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");

pub const InsertSizeStage = struct {
    const MAX_INSERT = 10000;
    insert_size_histogram: [MAX_INSERT]usize = [_]usize{0} ** MAX_INSERT,
    sum_insert_size: u64 = 0,
    count: usize = 0,
    min_insert_size: i32 = std.math.maxInt(i32),
    max_insert_size: i32 = 0,
    mean_insert_size: f64 = 0.0,

    pub fn process(ptr: *anyopaque, record: *bam_reader.AlignmentRecord) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if ((record.flag & 1) != 0 and (record.flag & 2) != 0) {
            const tlen = if (record.template_length < 0) -record.template_length else record.template_length;
            if (tlen > 0) {
                if (tlen < self.min_insert_size) self.min_insert_size = tlen;
                if (tlen > self.max_insert_size) self.max_insert_size = tlen;
                self.sum_insert_size += @intCast(tlen);
                self.count += 1;
                const idx: usize = if (tlen >= MAX_INSERT) MAX_INSERT - 1 else @intCast(tlen);
                self.insert_size_histogram[idx] += 1;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.count > 0) {
            self.mean_insert_size = @as(f64, @floatFromInt(self.sum_insert_size)) / @as(f64, @floatFromInt(self.count));
        } else {
            self.min_insert_size = 0;
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Insert Size Report:\n", .{}) catch {};
        writer.print("  Pairs analyzed: {d}\n", .{self.count}) catch {};
        writer.print("  Min insert:     {d}\n", .{self.min_insert_size}) catch {};
        writer.print("  Max insert:     {d}\n", .{self.max_insert_size}) catch {};
        writer.print("  Mean insert:    {d:.2}\n", .{self.mean_insert_size}) catch {};
        
        if (self.count > 0) {
            writer.print("  Histogram (Condensed):\n", .{}) catch {};
            var i: usize = 0;
            while (i < MAX_INSERT) : (i += 500) {
                var bin_sum: usize = 0;
                var j: usize = 0;
                while (j < 500 and i + j < MAX_INSERT) : (j += 1) {
                    bin_sum += self.insert_size_histogram[i + j];
                }
                if (bin_sum > 0) {
                    writer.print("    {d}-{d} bp: {d}\n", .{ i, i + 500, bin_sum }) catch {};
                }
            }
        }
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print(
            \\"insert_size": {{
            \\  "pairs_analyzed": {d},
            \\  "min_insert": {d},
            \\  "max_insert": {d},
            \\  "mean_insert": {d:.2},
            \\  "histogram_500bp_bins": [
        , .{ self.count, self.min_insert_size, self.max_insert_size, self.mean_insert_size });
        
        var i: usize = 0;
        var first = true;
        while (i < MAX_INSERT) : (i += 500) {
            var bin_sum: usize = 0;
            var j: usize = 0;
            while (j < 500 and i + j < MAX_INSERT) : (j += 1) {
                bin_sum += self.insert_size_histogram[i + j];
            }
            if (!first) try writer.writeAll(", ");
            try writer.print("{d}", .{bin_sum});
            first = false;
        }
        try writer.writeAll("] }");
    }

    pub fn stage(self: *@This()) bam_stage.BamStage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
                .reportJson = reportJson,
            },
        };
    }
};
