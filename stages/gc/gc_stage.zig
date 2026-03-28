const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const simd = @import("simd_ops");
const fastq_block = @import("fastq_block");
const column_ops = @import("column_ops");
const bitplanes = @import("bitplanes");

pub const GcStage = struct {
    gc_bases: usize = 0,
    total_bases: usize = 0,
    gc_ratio: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_bases += read.seq.len;
        if (simd.simd_enabled()) {
            self.gc_bases += simd.countGcSimd(read.seq);
        } else {
            for (read.seq) |base| {
                if (base == 'G' or base == 'C' or base == 'g' or base == 'c') self.gc_bases += 1;
            }
        }
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes.BitplaneCore, block: *const fastq_block.FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        // Use pre-computed results from bitplanes
        const results = @constCast(bp).getFused(block.read_count);
        self.gc_bases += results.gc_count;
        self.total_bases += results.total_bases;
        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const fastq_block.FastqColumnBlock) !bool {
        var bp = try bitplanes.BitplaneCore.init(block.allocator, block.capacity, block.max_read_len);
        defer bp.deinit();
        bp.fromColumnBlock(block);
        return processBitplanes(ptr, &bp, block);
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_bases > 0) {
            self.gc_ratio = @as(f64, @floatFromInt(self.gc_bases)) / @as(f64, @floatFromInt(self.total_bases));
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.gc_bases += other.gc_bases;
        self.total_bases += other.total_bases;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("GC Report:\n", .{}) catch {};
        writer.print("  GC Content: {d:.2}%\n", .{self.gc_ratio * 100.0}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print(
            \\"gc": {{
            \\  "gc_ratio": {d:.4}
            \\}}
        , .{self.gc_ratio});
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .processBlock = processBlock,
                .processBitplanes = processBitplanes,
                .finalize = finalize,
                .report = report,
                .reportJson = reportJson,
                .merge = merge,
            },
        };
    }
};
