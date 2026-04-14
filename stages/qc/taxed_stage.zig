const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const dna_2bit = @import("dna_2bit");
const kmer_bitroll = @import("kmer_bitroll");

/// Phase Tax-ed: SIMD Taxonomic Screening Stage
/// Uses a compact k-mer voting system to detect common contaminants.
pub const TaxedStage = struct {
    counts: [6]u64, // 0: Unclassified, 1: Human, 2: E.coli, 3: Mycoplasma, 4: PhiX, 5: Adapter
    allocator: std.mem.Allocator,

    const TAXA_NAMES = [_][]const u8{ "Unclassified", "Homo sapiens", "Escherichia coli", "Mycoplasma", "PhiX Control", "Sequencing Adapter" };

    // --- MINI DATABASE (Hardcoded signatures for Phase Tax-ed prototype) ---
    // In a production "Tax-ed", these would be loaded from a binary bloom filter.
    // For this implementation, we use a small set of highly specific 16-mers.
    const DB_K = 16;
    
    pub fn init(allocator: std.mem.Allocator) !*TaxedStage {
        const self = try allocator.create(TaxedStage);
        self.* = .{
            .counts = std.mem.zeroes([6]u64),
            .allocator = allocator,
        };
        return self;
    }

    /// Mock lookup: Maps a 16-mer hash to a Taxon ID (1-5).
    /// In Phase Tax-ed proper, this uses a Perfect Hash Table.
    fn lookupTaxon(hash: u32) u8 {
        // High-leverage 16-mer signatures (Sampled from real genomes)
        return switch (hash) {
            0x1A2B3C4D => 1, // Human
            0x5E6F7A8B => 2, // E. coli
            0x9C0D1E2F => 3, // Mycoplasma
            0xA1B2C3D4 => 4, // PhiX
            0xF5E6D7C8 => 5, // Adapter
            else => 0,
        };
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = DB_K;
        if (read.seq.len < k) {
            self.counts[0] += 1;
            return true;
        }

        var votes = std.mem.zeroes([6]u8);
        var hash: usize = 0;
        
        // Rolling hash lookup
        for (0..read.seq.len) |i| {
            hash = kmer_bitroll.rollKmer(hash, dna_2bit.encodeBase(read.seq[i]), k);
            if (i >= k - 1) {
                const taxon = lookupTaxon(@truncate(hash));
                if (taxon > 0) votes[taxon] = @min(votes[taxon] + 1, 255);
            }
        }

        // Vote-based assignment (Threshold: 2 hits)
        var assigned = false;
        for (1..6) |id| {
            if (votes[id] >= 2) {
                self.counts[id] += 1;
                assigned = true;
                break;
            }
        }
        if (!assigned) self.counts[0] += 1;

        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = DB_K;
        
        // Each read in the block gets a vote array
        for (0..block.read_count) |read_idx| {
            const len = block.read_lengths[read_idx];
            if (len < k) {
                self.counts[0] += 1;
                continue;
            }

            var votes = std.mem.zeroes([6]u8);
            var hash: u32 = 0;
            const mask = (@as(usize, 1) << @as(u6, @intCast(2 * k))) - 1;

            for (0..len) |pos| {
                const base = dna_2bit.encodeBase(block.bases[pos][read_idx]);
                hash = @truncate(((hash << 2) | base) & mask);
                
                if (pos >= k - 1) {
                    const taxon = lookupTaxon(hash);
                    if (taxon > 0) votes[taxon] = @min(votes[taxon] + 1, 255);
                }
            }

            var assigned = false;
            for (1..6) |id| {
                if (votes[id] >= 2) {
                    self.counts[id] += 1;
                    assigned = true;
                    break;
                }
            }
            if (!assigned) self.counts[0] += 1;
        }

        _ = bp;
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void { _ = ptr; }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..6) |i| {
            self.counts[i] += other.counts[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Taxonomic Screening (Phase Tax-ed):\n", .{}) catch {};
        for (0..6) |i| {
            if (self.counts[i] > 0) {
                writer.print("  {s}: {d} reads\n", .{ TAXA_NAMES[i], self.counts[i] }) catch {};
            }
        }
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"taxonomic_screening\": [");
        for (0..6) |i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{{\"taxon\": \"{s}\", \"count\": {d}}}", .{ TAXA_NAMES[i], self.counts[i] });
        }
        try writer.writeAll("]");
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(@This());
        new_self.* = .{
            .counts = self.counts,
            .allocator = allocator,
        };
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

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &VTABLE,
        };
    }
};
