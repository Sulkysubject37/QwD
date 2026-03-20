const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const simd = @import("simd_ops");
const fastq_block = @import("fastq_block");
const column_ops = @import("column_ops");

pub const QcStage = struct {
    total_reads: usize = 0,
    total_bases: usize = 0,
    sum_quality: u64 = 0,
    mean_quality: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        self.total_bases += read.seq.len;
        
        if (simd.simd_enabled()) {
            self.sum_quality += simd.sumPhredSimd(read.qual);
        } else {
            for (read.qual) |q| {
                const phred = if (q >= 33) q - 33 else 0;
                self.sum_quality += phred;
            }
        }
        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const fastq_block.FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += block.read_count;
        
        for (0..block.read_count) |i| {
            self.total_bases += block.read_lengths[i];
        }

        // Columnar quality summation
        for (0..block.max_read_len) |col| {
            // Only process column if at least one read has data here
            // But we can just use the count and assume shorter reads have 0/dummy qualities
            self.sum_quality += column_ops.sumQualityColumn(block.qualities[col], block.read_count);
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_bases > 0) {
            self.mean_quality = @as(f64, @floatFromInt(self.sum_quality)) / @as(f64, @floatFromInt(self.total_bases));
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.total_bases += other.total_bases;
        self.sum_quality += other.sum_quality;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("QC Report:\n", .{}) catch {};
        writer.print("  Total reads: {d}\n", .{self.total_reads}) catch {};
        writer.print("  Total bases: {d}\n", .{self.total_bases}) catch {};
        writer.print("  Mean quality: {d:.2}\n", .{self.mean_quality}) catch {};
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .processBlock = processBlock,
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
