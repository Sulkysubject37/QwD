const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const NucleotideCompositionStage = struct {
    const MAX_POS = 10000;
    // Global counters for all positions combined
    global_counts: [4]u64 = [_]u64{0} ** 4,
    // Detailed per-position counters
    base_counts: [MAX_POS][4]u64 = [_][4]u64{[_]u64{0} ** 4} ** MAX_POS,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const limit = if (read.seq.len > MAX_POS) MAX_POS else read.seq.len;
        for (0..limit) |pos| {
            switch (read.seq[pos]) {
                'A', 'a' => self.base_counts[pos][0] += 1,
                'C', 'c' => self.base_counts[pos][1] += 1,
                'G', 'g' => self.base_counts[pos][2] += 1,
                'T', 't' => self.base_counts[pos][3] += 1,
                else => {},
            }
        }
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        
        for (0..block.max_read_len) |col| {
            if (col >= MAX_POS) break;
            const col_offset = col * bp.u64_per_col;
            const u64_count = (block.read_count + 63) / 64;
            
            for (0..u64_count) |i| {
                const idx = col_offset + i;
                self.base_counts[col][0] += @popCount(bp.plane_a[idx]);
                self.base_counts[col][1] += @popCount(bp.plane_c[idx]);
                self.base_counts[col][2] += @popCount(bp.plane_g[idx]);
                self.base_counts[col][3] += @popCount(bp.plane_t[idx]);
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
            const limit = if (read.seq.len > MAX_POS) MAX_POS else read.seq.len;
            for (0..limit) |pos| {
                switch (read.seq[pos]) {
                    'A', 'a' => self.base_counts[pos][0] += 1,
                    'C', 'c' => self.base_counts[pos][1] += 1,
                    'G', 'g' => self.base_counts[pos][2] += 1,
                    'T', 't' => self.base_counts[pos][3] += 1,
                    else => {},
                }
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (0..MAX_POS) |pos| {
            self.global_counts[0] += self.base_counts[pos][0];
            self.global_counts[1] += self.base_counts[pos][1];
            self.global_counts[2] += self.base_counts[pos][2];
            self.global_counts[3] += self.base_counts[pos][3];
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..4) |i| self.global_counts[i] += other.global_counts[i];
        for (0..MAX_POS) |i| {
            for (0..4) |j| self.base_counts[i][j] += other.base_counts[i][j];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Nucleotide Composition Report (Global):\n", .{}) catch {};
        writer.print("  A={d}, C={d}, G={d}, T={d}\n", .{
            self.global_counts[0], self.global_counts[1], self.global_counts[2], self.global_counts[3],
        }) catch {};
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
