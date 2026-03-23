const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const PerBaseQualityStage = struct {
    const MAX_POS = 10000;
    quality_sum: [MAX_POS]u64 = [_]u64{0} ** MAX_POS,
    base_count: [MAX_POS]u64 = [_]u64{0} ** MAX_POS,
    mean_quality: [MAX_POS]f64 = [_]f64{0.0} ** MAX_POS,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const limit = if (read.qual.len > MAX_POS) MAX_POS else read.qual.len;
        for (0..limit) |pos| {
            const q = read.qual[pos];
            const phred = if (q >= 33) q - 33 else 0;
            self.quality_sum[pos] += phred;
            self.base_count[pos] += 1;
        }
        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const column_ops = @import("column_ops");
        
        for (0..block.max_read_len) |col| {
            if (col >= MAX_POS) break;
            
            // Count how many reads actually cover this position
            var coverage: usize = 0;
            for (0..block.read_count) |i| {
                if (block.read_lengths[i] > col) coverage += 1;
            }
            
            if (coverage > 0) {
                self.quality_sum[col] += column_ops.sumQualityColumn(block.qualities[col], block.read_count);
                self.base_count[col] += coverage;
            }
        }
        return true;
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (reads) |read| {
            const limit = if (read.qual.len > MAX_POS) MAX_POS else read.qual.len;
            for (0..limit) |pos| {
                const q = read.qual[pos];
                const phred = if (q >= 33) q - 33 else 0;
                self.quality_sum[pos] += phred;
                self.base_count[pos] += 1;
            }
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

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..MAX_POS) |i| {
            self.quality_sum[i] += other.quality_sum[i];
            self.base_count[i] += other.base_count[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Per-base Quality Report (first 10 positions):\n", .{}) catch {};
        const limit = if (MAX_POS > 10) 10 else MAX_POS;
        for (0..limit) |pos| {
            if (self.base_count[pos] > 0) {
                writer.print("  Pos {d}: {d:.2}\n", .{ pos, self.mean_quality[pos] }) catch {};
            }
        }
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"per_base_quality\": { \"mean_qualities\": [");
        var first = true;
        for (0..MAX_POS) |pos| {
            if (self.base_count[pos] == 0) break;
            if (!first) try writer.writeAll(", ");
            try writer.print("{d:.2}", .{self.mean_quality[pos]});
            first = false;
        }
        try writer.writeAll("] }");
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
