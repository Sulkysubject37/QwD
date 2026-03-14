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

    fn baseToIndex(base: u8) ?u2 {
        return switch (base) {
            'A', 'a' => 0,
            'C', 'c' => 1,
            'G', 'g' => 2,
            'T', 't' => 3,
            else => null,
        };
    }

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        const seq = read.seq;
        if (seq.len < self.suffix_length) return true;

        const suffix = seq[seq.len - self.suffix_length ..];
        
        for (0..self.suffix_length - k + 1) |i| {
            const kmer = suffix[i .. i + k];
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
                self.total_suffix_kmers += 1;
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
        self.total_suffix_kmers += other.total_suffix_kmers;
        for (0..self.counts.len) |i| {
            self.counts[i] += other.counts[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Adapter Detection Report:\n", .{}) catch {};
        writer.print("  Total suffix k-mers analyzed: {d}\n", .{self.total_suffix_kmers}) catch {};
        
        if (self.total_suffix_kmers == 0) return;

        // Find top k-mer
        var max_count: u64 = 0;
        var max_idx: usize = 0;
        for (self.counts, 0..) |count, idx| {
            if (count > max_count) {
                max_count = count;
                max_idx = idx;
            }
        }

        if (max_count > (self.total_suffix_kmers / 10)) { // 10% threshold
            writer.print("  Potential adapter detected! Most frequent suffix k-mer (count={d}): ", .{max_count}) catch {};
            var i: usize = 0;
            const idx_copy = max_idx;
            var kmer_buf: [8]u8 = undefined;
            while (i < 8) : (i += 1) {
                const b = @as(u2, @truncate(idx_copy >> @as(u6, @intCast(2 * (7 - i)))));
                kmer_buf[i] = switch (b) {
                    0 => 'A',
                    1 => 'C',
                    2 => 'G',
                    3 => 'T',
                };
            }
            writer.print("{s}\n", .{kmer_buf}) catch {};
        } else {
            writer.print("  No frequent adapter k-mer detected.\n", .{}) catch {};
        }
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
