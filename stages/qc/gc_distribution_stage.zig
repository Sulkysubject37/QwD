const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const GcDistributionStage = struct {
    // bins: 0-10, 10-20, ..., 90-100 (10 bins)
    histogram: [10]usize = [_]usize{0} ** 10,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        if (len == 0) return true;

        var gc_count: usize = 0;
        for (read.seq) |base| {
            if (base == 'G' or base == 'C' or base == 'g' or base == 'c') {
                gc_count += 1;
            }
        }

        const gc_ratio = @as(f64, @floatFromInt(gc_count)) / @as(f64, @floatFromInt(len));
        var bin = @as(usize, @intFromFloat(gc_ratio * 10.0));
        if (bin == 10) bin = 9; // handle 100%

        self.histogram[bin] += 1;

        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").Bitplanes, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));

        for (0..block.read_count) |read_idx| {
            var gc_count: usize = 0;
            const word_idx = read_idx >> 6;
            const bit_mask = @as(u64, 1) << @as(u6, @intCast(read_idx & 63));

            for (0..block.read_lengths[read_idx]) |col| {
                const col_offset = col * bp.u64_per_col;
                if ((bp.plane_g[col_offset + word_idx] | bp.plane_c[col_offset + word_idx]) & bit_mask != 0) {
                    gc_count += 1;
                }
            }

            const len = block.read_lengths[read_idx];
            if (len > 0) {
                const gc_ratio = @as(f64, @floatFromInt(gc_count)) / @as(f64, @floatFromInt(len));
                var bin = @as(usize, @intFromFloat(gc_ratio * 10.0));
                if (bin == 10) bin = 9;
                self.histogram[bin] += 1;
            }
        }

        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const bitplanes = @import("bitplanes");
        var bp = try bitplanes.Bitplanes.init(block.allocator, block.capacity, block.max_read_len);
        defer bp.deinit();
        bp.fromColumnBlock(block);
        return processBitplanes(ptr, &bp, block);
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (reads) |read| {
            const len = read.seq.len;
            if (len == 0) continue;

            var gc_count: usize = 0;
            for (read.seq) |base| {
                if (base == 'G' or base == 'C' or base == 'g' or base == 'c') {
                    gc_count += 1;
                }
            }

            const gc_ratio = @as(f64, @floatFromInt(gc_count)) / @as(f64, @floatFromInt(len));
            var bin = @as(usize, @intFromFloat(gc_ratio * 10.0));
            if (bin == 10) bin = 9;

            self.histogram[bin] += 1;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..10) |i| {
            self.histogram[i] += other.histogram[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("GC Distribution Report:\n", .{}) catch {};
        for (0..10) |i| {
            writer.print("  {d}0-{d}0%: {d}\n", .{ i, i + 1, self.histogram[i] }) catch {};
        }
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .processRawBatch = processRawBatch,
                .processBlock = processBlock,
                .processBitplanes = processBitplanes,
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
