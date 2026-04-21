const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const kmer_counter = @import("kmer_counter");

const bitplanes = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const KmerSpectrumStage = struct {
    k: usize = 11,
    counter: kmer_counter.KmerCounter,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, k: usize) KmerSpectrumStage {
        return .{
            .k = k,
            .allocator = allocator,
            .counter = kmer_counter.KmerCounter.init(allocator, k) catch unreachable,
        };
    }

    pub fn deinit(self: *KmerSpectrumStage) void {
        self.counter.deinit();
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (read.seq.len < self.k) return true;

        var packed_val: u64 = 0;
        var valid_len: usize = 0;
        for (read.seq) |b| {
            var val: u64 = 0;
            var is_n = false;
            switch (b) {
                'A', 'a' => val = 0,
                'C', 'c' => val = 1,
                'G', 'g' => val = 2,
                'T', 't' => val = 3,
                else => is_n = true,
            }
            if (is_n) {
                valid_len = 0;
                packed_val = 0;
            } else {
                packed_val = ((packed_val << 2) | val) & ((@as(u64, 1) << (@as(u6, @intCast(self.k)) * 2)) - 1);
                valid_len += 1;
                if (valid_len >= self.k) self.counter.add(packed_val);
            }
        }
        return true;
    }

    /// HIGH-SPEED BITPLANE K-MER COUNTING (Phase S Optimized)
    /// Processes 64 reads in parallel using 2-bit rolling hashes.
    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        
        const u64_count = (block.read_count + 63) / 64;
        const k_mask = (@as(u64, 1) << (@as(u6, @intCast(k)) * 2)) - 1;

        for (0..u64_count) |word_idx| {
            // PHASE S: High-Throughput Word-Parallel Kernels
            var packed_kmers = [_]u64{0} ** 64;
            var valid_lens = [_]u8{0} ** 64;

            var word_max_len: u16 = 0;
            const group_start = word_idx * 64;
            const group_end = @min(group_start + 64, block.read_count);
            for (group_start..group_end) |read_idx| {
                word_max_len = @max(word_max_len, block.read_lengths[read_idx]);
            }

            for (0..word_max_len) |col| {
                const bp_off = col * bp.u64_per_col + word_idx;
                const c = bp.plane_c[bp_off];
                const g = bp.plane_g[bp_off];
                const t = bp.plane_t[bp_off];
                const n = bp.plane_n[bp_off];
                const active_mask = bp.plane_mask[bp_off];

                if (active_mask == 0) {
                    for (0..64) |b_idx| valid_lens[b_idx] = 0;
                    continue;
                }

                // 2-BIT ROLLING BITPLANE UPDATE
                // We use bitplanes directly to update all 64 kmers.
                // A=00, C=01, G=10, T=11 (as defined in Phase S)
                for (0..64) |b_idx| {
                    const bit = @as(u64, 1) << @as(u6, @intCast(b_idx));
                    if ((active_mask & bit) == 0 or (n & bit) != 0) {
                        valid_lens[b_idx] = 0;
                        continue;
                    }

                    // Extract 2 bits: 
                    // Bit 0: C or T
                    // Bit 1: G or T
                    const b0 = @as(u64, @intFromBool((c & bit) != 0 or (t & bit) != 0));
                    const b1 = @as(u64, @intFromBool((g & bit) != 0 or (t & bit) != 0));
                    const val = b0 | (b1 << 1);

                    packed_kmers[b_idx] = ((packed_kmers[b_idx] << 2) | val) & k_mask;
                    valid_lens[b_idx] += 1;
                    if (valid_lens[b_idx] >= k) {
                        self.counter.add(packed_kmers[b_idx]);
                    }
                }
            }
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}

    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        var top = [3]usize{ 0, 0, 0 };
        self.counter.getTop(&top);
        try writer.print("\"kmer_spectrum\": {{\"k\": {d}, \"counts\": [{d},{d},{d}]}}", .{
            self.k, top[0], top[1], top[2],
        }); 
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.counter.merge(&other.counter);
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(KmerSpectrumStage);
        new_self.* = KmerSpectrumStage.init(allocator, self.k);
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = KmerSpectrumStage.process,
    .finalize = KmerSpectrumStage.finalize,
    .report = KmerSpectrumStage.report,
    .reportJson = KmerSpectrumStage.reportJson,
    .merge = KmerSpectrumStage.merge,
    .clone = KmerSpectrumStage.clone,
    .processBitplanes = KmerSpectrumStage.processBitplanes,
};
