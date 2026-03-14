const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const dna_2bit = @import("dna_2bit");
const kmer_bitroll = @import("kmer_bitroll");

pub const KmerSpectrumStage = struct {
    k: u8 = 5,
    counts: []u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !KmerSpectrumStage {
        const k: u8 = 5;
        const size = std.math.pow(usize, 4, k);
        const counts = try allocator.alloc(u64, size);
        @memset(counts, 0);
        return KmerSpectrumStage{
            .k = k,
            .counts = counts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KmerSpectrumStage) void {
        self.allocator.free(self.counts);
    }

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        if (read.seq.len < k) return true;

        var hash: usize = 0;
        
        // Initialize first window
        for (0..k) |i| {
            hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(read.seq[i]), k);
        }
        self.counts[hash] += 1;

        // Rolling hash for the rest
        for (k..read.seq.len) |i| {
            hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(read.seq[i]), k);
            self.counts[hash] += 1;
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

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
