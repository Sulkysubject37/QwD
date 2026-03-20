const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const dna_2bit = @import("dna_2bit");
const kmer_columnar = @import("kmer_columnar");

pub const KmerStage = struct {
    k: u8,
    counts: []u64,
    allocator: std.mem.Allocator,
    total_kmers: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, k: u8) !KmerStage {
        const size = std.math.pow(usize, 4, k);
        const counts = try allocator.alloc(u64, size);
        @memset(counts, 0);
        return KmerStage{
            .k = k,
            .counts = counts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KmerStage) void {
        self.allocator.free(self.counts);
    }

    fn baseToIndex(base: u8) ?u2 {
        return switch (base) {
            'A', 'a' => 0,
            'C', 'c' => 1,
            'G', 'g' => 2,
            'T', 't' => 3,
            else => null,
        };
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        if (read.seq.len < k) return true;

        for (0..read.seq.len - k + 1) |i| {
            const kmer = read.seq[i .. i + k];
            var index: usize = 0;
            var valid = true;
            for (kmer) |b| {
                const b_idx = baseToIndex(b) orelse {
                    valid = false;
                    break;
                };
                index = (index << 2) | b_idx;
            }
            if (valid) {
                self.counts[index] += 1;
                self.total_kmers += 1;
            }
        }

        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").Bitplanes, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        _ = bp;
        return processBlock(ptr, block);
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        const vec_size = 32;

        var read_idx: usize = 0;
        while (read_idx + vec_size <= block.read_count) : (read_idx += vec_size) {
            var hashes: @Vector(vec_size, u32) = @splat(0);
            
            // Prime the hashes with the first (k-1) bases
            for (0..k-1) |i| {
                const bases: @Vector(vec_size, u8) = block.bases[i][read_idx..][0..vec_size].*;
                hashes = kmer_columnar.updateKmerHashes(hashes, bases, k);
            }
            
            for (k-1..block.max_read_len) |i| {
                const bases: @Vector(vec_size, u8) = block.bases[i][read_idx..][0..vec_size].*;
                hashes = kmer_columnar.updateKmerHashes(hashes, bases, k);
                
                // Add to counts if read hasn't ended and no Ns
                // This is simple scatter; wait, kmer_columnar masks automatically.
                for (0..vec_size) |j| {
                    if (i < block.read_lengths[read_idx + j]) {
                        self.counts[hashes[j]] += 1;
                        self.total_kmers += 1;
                    }
                }
            }
        }

        // Residual reads handling
        while (read_idx < block.read_count) : (read_idx += 1) {
            const len = block.read_lengths[read_idx];
            if (len < k) continue;

            for (0..len - k + 1) |pos| {
                var index: usize = 0;
                var valid = true;
                for (0..k) |i| {
                    const b = block.bases[pos + i][read_idx];
                    const b_idx = baseToIndex(b) orelse {
                        valid = false;
                        break;
                    };
                    index = (index << 2) | b_idx;
                }
                if (valid) {
                    self.counts[index] += 1;
                    self.total_kmers += 1;
                }
            }
        }

        return true;
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        for (reads) |read| {
            _ = try process(ptr, &read);
        }
        return true;
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..self.counts.len) |i| {
            self.counts[i] += other.counts[i];
        }
        self.total_kmers += other.total_kmers;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("k-mer Report (k={d}):\n", .{self.k}) catch {};
        writer.print("  Total k-mers: {d}\n", .{self.total_kmers}) catch {};
        // For brevity, we don't print all 4^k counts unless small
        if (self.total_kmers > 0 and self.k <= 3) {
            // Print top k-mers or just first few for illustration
            writer.print("  (Counts omitted for brevity in CLI report)\n", .{}) catch {};
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
