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

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const k = self.k;
        const seq = read.seq;
        if (seq.len < self.suffix_length) return true;

        const suffix = seq[seq.len - self.suffix_length ..];
        
        // Fast base to index
        // Use rolling hash logic here too
        var hash: usize = 0;
        for (0..k) |i| {
            const b = suffix[i];
            const idx: usize = switch (b) {
                'A', 'a' => 0,
                'C', 'c' => 1,
                'G', 'g' => 2,
                'T', 't' => 3,
                else => 0,
            };
            hash = (hash << 2) | idx;
        }
        self.counts[hash & 0xFFFF] += 1; // 4^8 = 65536
        self.total_suffix_kmers += 1;

        for (k..self.suffix_length) |i| {
            const b = suffix[i];
            const idx: usize = switch (b) {
                'A', 'a' => 0,
                'C', 'c' => 1,
                'G', 'g' => 2,
                'T', 't' => 3,
                else => 0,
            };
            hash = ((hash << 2) | idx) & 0xFFFF;
            self.counts[hash] += 1;
            self.total_suffix_kmers += 1;
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

        var max_count: u64 = 0;
        var max_idx: usize = 0;
        for (self.counts, 0..) |count, idx| {
            if (count > max_count) {
                max_count = count;
                max_idx = idx;
            }
        }

        if (max_count > (self.total_suffix_kmers / 10)) {
            writer.print("  Potential adapter detected! Most frequent suffix k-mer (count={d})\n", .{max_count}) catch {};
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
