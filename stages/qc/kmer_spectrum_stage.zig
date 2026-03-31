const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const dna_2bit = @import("dna_2bit");
const kmer_bitroll = @import("kmer_bitroll");

pub const KmerSpectrumStage = struct {
    k: u8 = 5,
    counts: []u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*KmerSpectrumStage {
        const k: u8 = 5;
        const size = std.math.pow(usize, 4, k);
        const counts = try allocator.alloc(u64, size);
        @memset(counts, 0);
        const self = try allocator.create(KmerSpectrumStage);
        self.* = KmerSpectrumStage{
            .k = k,
            .counts = counts,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *KmerSpectrumStage) void {
        self.allocator.free(self.counts);
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        if (read.seq.len < k) return true;

        var hash: usize = 0;
        for (0..k) |i| {
            hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(read.seq[i]), k);
        }
        self.counts[hash] += 1;

        for (k..read.seq.len) |i| {
            hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(read.seq[i]), k);
            self.counts[hash] += 1;
        }

        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const kmer_columnar = @import("kmer_columnar");
        const k = self.k;
        const vec_size = 32;

        var read_idx: usize = 0;
        while (read_idx + vec_size <= block.read_count) : (read_idx += vec_size) {
            var hashes: @Vector(vec_size, u32) = @splat(@as(u32, 0));
            
            // Initialization: Fill first k-1 bases
            for (0..k-1) |i| {
                const col_bases: @Vector(vec_size, u8) = block.bases[i][read_idx..][0..vec_size].*;
                hashes = kmer_columnar.updateKmerHashes(hashes, col_bases, k);
            }

            // Rolling hash across the rest of the reads
            for (k-1..block.max_read_len) |i| {
                const col_bases: @Vector(vec_size, u8) = block.bases[i][read_idx..][0..vec_size].*;
                hashes = kmer_columnar.updateKmerHashes(hashes, col_bases, k);
                
                // For each read in the vector, check if it hasn't reached its end
                inline for (0..vec_size) |v_idx| {
                    if (i < block.read_lengths[read_idx + v_idx]) {
                        self.counts[hashes[v_idx]] += 1;
                    }
                }
            }
        }

        // Residual scalar handling
        while (read_idx < block.read_count) : (read_idx += 1) {
            const len = block.read_lengths[read_idx];
            if (len < k) continue;

            var hash: usize = 0;
            for (0..k) |i| {
                hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(block.bases[i][read_idx]), k);
            }
            self.counts[hash] += 1;

            for (k..len) |i| {
                hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(block.bases[i][read_idx]), k);
                self.counts[hash] += 1;
            }
        }

        _ = bp;
        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;

        for (0..block.read_count) |read_idx| {
            const len = block.read_lengths[read_idx];
            if (len < k) continue;

            var hash: usize = 0;
            for (0..k) |i| {
                hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(block.bases[i][read_idx]), k);
            }
            self.counts[hash] += 1;

            for (k..len) |i| {
                hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(block.bases[i][read_idx]), k);
                self.counts[hash] += 1;
            }
        }

        return true;
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        for (reads) |read| {
            if (read.seq.len < k) continue;

            var hash: usize = 0;
            for (0..k) |i| {
                hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(read.seq[i]), k);
            }
            self.counts[hash] += 1;

            for (k..read.seq.len) |i| {
                hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(read.seq[i]), k);
                self.counts[hash] += 1;
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
        for (0..self.counts.len) |i| {
            self.counts[i] += other.counts[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("K-mer Spectrum Report (k={d}):\n", .{self.k}) catch {};
        var total: u64 = 0;
        for (self.counts) |c| total += c;
        writer.print("  Total {d}-mers: {d}\n", .{self.k, total}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"kmer_spectrum\": {{ \"k\": {d}, \"counts\": [", .{self.k});
        for (self.counts, 0..) |count, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{count});
        }
        try writer.writeAll("] }");
    }

    pub fn stage(self: *const @This()) stage_mod.Stage {
        return .{
            .ptr = @constCast(self),
            .vtable = &.{
                .process = process,
                .processRawBatch = processRawBatch,
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
