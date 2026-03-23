const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const LengthDistributionStage = struct {
    read_count_per_bin: [6]usize = [_]usize{0} ** 6,
    total_reads: usize = 0,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
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

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += block.read_count;

        for (0..block.read_count) |i| {
            const len = block.read_lengths[i];
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
        }

        return true;
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (reads) |read| {
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
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        for (0..6) |i| {
            self.read_count_per_bin[i] += other.read_count_per_bin[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Read Length Distribution Report:\n", .{}) catch {};
        writer.print("  0-100:     {d}\n", .{self.read_count_per_bin[0]}) catch {};
        writer.print("  100-500:   {d}\n", .{self.read_count_per_bin[1]}) catch {};
        writer.print("  500-1000:  {d}\n", .{self.read_count_per_bin[2]}) catch {};
        writer.print("  1000-5000: {d}\n", .{self.read_count_per_bin[3]}) catch {};
        writer.print("  5000-10000:{d}\n", .{self.read_count_per_bin[4]}) catch {};
        writer.print("  10000+:    {d}\n", .{self.read_count_per_bin[5]}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print(
            \\"length_distribution": {{
            \\  "bins": [{d}, {d}, {d}, {d}, {d}, {d}]
            \\}}
        , .{
            self.read_count_per_bin[0], self.read_count_per_bin[1], self.read_count_per_bin[2],
            self.read_count_per_bin[3], self.read_count_per_bin[4], self.read_count_per_bin[5],
        });
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .processRawBatch = processRawBatch,
                .processBlock = processBlock,
                .finalize = finalize,
                .report = report,
                .reportJson = reportJson,
                .merge = merge,
            },
        };
    }
};
