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

    pub fn init(allocator: std.mem.Allocator) !*QcStage {
        const self = try allocator.create(QcStage);
        self.* = .{};
        return self;
    }

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

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const res = @constCast(bp).getFused(block.read_count);
        self.total_reads += block.read_count;
        self.total_bases += res.total_bases;

        // Columnar quality summation
        for (0..block.max_read_len) |col| {
            self.sum_quality += column_ops.sumQualityColumn(block.qualities[col], block.read_count);
        }

        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const fastq_block.FastqColumnBlock) !bool {
        const bitplanes = @import("bitplanes");
        var bp = try bitplanes.BitplaneCore.init(block.allocator, block.capacity, block.max_read_len);
        defer bp.deinit();
        bp.fromColumnBlock(block);
        return processBitplanes(ptr, &bp, block);
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

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"qc\": {{\"total_reads\": {d}, \"total_bases\": {d}, \"mean_quality\": {d:.2}}}", .{ self.total_reads, self.total_bases, self.mean_quality });
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(@This());
        new_self.* = self.*;
        return new_self;
    }

    const VTABLE = stage_mod.Stage.VTable{
        .process = process,
        .processBitplanes = processBitplanes,
        .finalize = finalize,
        .report = report,
        .reportJson = reportJson,
        .merge = merge,
        .clone = clone,
    };

    pub fn stage(self: *const @This()) stage_mod.Stage {
        return .{
            .ptr = @constCast(self),
            .vtable = &VTABLE,
        };
    }
};
