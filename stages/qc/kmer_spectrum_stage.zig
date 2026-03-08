const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

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
            }
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("K-mer Spectrum Report (k={d}):\n", .{self.k});
        var total: u64 = 0;
        for (self.counts) |c| total += c;
        std.debug.print("  Total {d}-mers: {d}\n", .{self.k, total});
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
