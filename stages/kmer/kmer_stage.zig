const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

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

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
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
                .finalize = finalize,
                .report = report,
            },
        };
    }
};
