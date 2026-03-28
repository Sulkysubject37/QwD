const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const AdapterDetectionStage = struct {
    k: u8 = 8,
    suffix_length: usize = 20,
    counts: []u64,
    allocator: std.mem.Allocator,
    total_suffix_kmers: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) !AdapterDetectionStage {
        const size = std.math.pow(usize, 4, 8);
        const counts = try allocator.alloc(u64, size);
        @memset(counts, 0);
        return AdapterDetectionStage{
            .counts = counts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AdapterDetectionStage) void {
        self.allocator.free(self.counts);
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        const seq = read.seq;
        if (seq.len < self.suffix_length) return true;
        const suffix = seq[seq.len - self.suffix_length ..];
        var hash: usize = 0;
        for (0..k) |i| {
            const idx: usize = switch (suffix[i]) {
                'A', 'a' => 0, 'C', 'c' => 1, 'G', 'g' => 2, 'T', 't' => 3, else => 0,
            };
            hash = (hash << 2) | idx;
        }
        self.counts[hash & 0xFFFF] += 1;
        self.total_suffix_kmers += 1;
        for (k..self.suffix_length) |i| {
            const idx: usize = switch (suffix[i]) {
                'A', 'a' => 0, 'C', 'c' => 1, 'G', 'g' => 2, 'T', 't' => 3, else => 0,
            };
            hash = ((hash << 2) | idx) & 0xFFFF;
            self.counts[hash] += 1;
            self.total_suffix_kmers += 1;
        }
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        _ = bp;

        for (0..block.read_count) |read_idx| {
            const len = block.read_lengths[read_idx];
            if (len < self.suffix_length) continue;

            const start = len - self.suffix_length;
            var hash: usize = 0;
            
            // Initialization for suffix
            for (0..k) |i| {
                const b = block.bases[start + i][read_idx];
                const idx: usize = switch (b) {
                    'A', 'a' => 0, 'C', 'c' => 1, 'G', 'g' => 2, 'T', 't' => 3, else => 0,
                };
                hash = (hash << 2) | idx;
            }
            self.counts[hash & 0xFFFF] += 1;
            self.total_suffix_kmers += 1;

            for (k..self.suffix_length) |i| {
                const b = block.bases[start + i][read_idx];
                const idx: usize = switch (b) {
                    'A', 'a' => 0, 'C', 'c' => 1, 'G', 'g' => 2, 'T', 't' => 3, else => 0,
                };
                hash = ((hash << 2) | idx) & 0xFFFF;
                self.counts[hash] += 1;
                self.total_suffix_kmers += 1;
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
        const k = self.k;
        for (reads) |read| {
            if (read.seq.len < self.suffix_length) continue;
            const suffix = read.seq[read.seq.len - self.suffix_length ..];
            var hash: usize = 0;
            for (0..k) |i| {
                const idx: usize = switch (suffix[i]) {
                    'A', 'a' => 0, 'C', 'c' => 1, 'G', 'g' => 2, 'T', 't' => 3, else => 0,
                };
                hash = (hash << 2) | idx;
            }
            self.counts[hash & 0xFFFF] += 1;
            self.total_suffix_kmers += 1;
            for (k..self.suffix_length) |i| {
                const idx: usize = switch (suffix[i]) {
                    'A', 'a' => 0, 'C', 'c' => 1, 'G', 'g' => 2, 'T', 't' => 3, else => 0,
                };
                hash = ((hash << 2) | idx) & 0xFFFF;
                self.counts[hash] += 1;
                self.total_suffix_kmers += 1;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void { _ = ptr; }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_suffix_kmers += other.total_suffix_kmers;
        for (0..self.counts.len) |i| self.counts[i] += other.counts[i];
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Adapter Detection Report:\n", .{}) catch {};
        writer.print("  Total suffix k-mers analyzed: {d}\n", .{self.total_suffix_kmers}) catch {};
        if (self.total_suffix_kmers == 0) return;
        var max_count: u64 = 0;
        for (self.counts) |count| if (count > max_count) { max_count = count; };
        if (max_count > (self.total_suffix_kmers / 10)) {
            writer.print("  Potential adapter detected! Most frequent suffix k-mer (count={d})\n", .{max_count}) catch {};
        } else {
            writer.print("  No frequent adapter k-mer detected.\n", .{}) catch {};
        }
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        var max_count: u64 = 0;
        for (self.counts) |count| if (count > max_count) { max_count = count; };
        try writer.print(
            \\"adapter_detection": {{
            \\  "total_suffix_kmers": {d},
            \\  "max_kmer_count": {d}
            \\}}
        , .{ self.total_suffix_kmers, max_count });
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
                .reportJson = reportJson,
                .merge = merge,
            },
        };
    }
};
