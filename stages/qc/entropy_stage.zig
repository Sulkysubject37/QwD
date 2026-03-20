const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const entropy_lut_mod = @import("entropy_lut");

pub const EntropyStage = struct {
    total_reads: usize = 0,
    total_entropy_sum: f64 = 0.0,
    low_complexity_reads: usize = 0,
    mean_entropy: f64 = 0.0,
    
    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
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

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));

        for (0..block.read_count) |read_idx| {
            var base_counts = [_]usize{0} ** 4;
            const word_idx = read_idx >> 6;
            const bit_mask = @as(u64, 1) << @as(u6, @intCast(read_idx & 63));

            for (0..block.read_lengths[read_idx]) |col| {
                const col_offset = col * bp.u64_per_col;
                if (bp.plane_a[col_offset + word_idx] & bit_mask != 0) {
                    base_counts[0] += 1;
                } else if (bp.plane_c[col_offset + word_idx] & bit_mask != 0) {
                    base_counts[1] += 1;
                } else if (bp.plane_g[col_offset + word_idx] & bit_mask != 0) {
                    base_counts[2] += 1;
                } else if (bp.plane_t[col_offset + word_idx] & bit_mask != 0) {
                    base_counts[3] += 1;
                }
            }

            const len = block.read_lengths[read_idx];
            if (len > 0) {
                const entropy = entropy_lut_mod.global_lut.getEntropy(base_counts, len);
                self.total_reads += 1;
                self.total_entropy_sum += entropy;
                if (entropy < 1.5) self.low_complexity_reads += 1;
            }
        }

        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const bitplanes = @import("bitplanes");
        var bp = try bitplanes.BitplaneCore.init(block.allocator, block.capacity, block.max_read_len);
        defer bp.deinit();
        bp.fromColumnBlock(block);
        return processBitplanes(ptr, &bp, block);
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (reads) |read| {
            const len = read.seq.len;
            if (len == 0) continue;

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
            if (entropy < 1.5) self.low_complexity_reads += 1;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_reads > 0) {
            self.mean_entropy = self.total_entropy_sum / @as(f64, @floatFromInt(self.total_reads));
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.total_entropy_sum += other.total_entropy_sum;
        self.low_complexity_reads += other.low_complexity_reads;
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
