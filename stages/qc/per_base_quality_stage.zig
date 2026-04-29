const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const PerbasequalityStage = struct {
    quality_counts: [1000][41]usize = [_][41]usize{[_]usize{0} ** 41} ** 1000,
    max_pos: usize = 0,

    pub fn deinit(self: *PerbasequalityStage, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool { 
        const self: *PerbasequalityStage = @ptrCast(@alignCast(ptr));
        const len = read.qual.len;
        if (len > self.max_pos) self.max_pos = len;
        for (read.qual, 0..) |q, i| {
            if (i >= 1000) break;
            const phred = if (q >= 33) @min(@as(usize, q - 33), 40) else 0;
            self.quality_counts[i][phred] += 1;
        }
        return true; 
    }

    pub fn processBitplanes(ptr: *anyopaque, _: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *PerbasequalityStage = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        const active_len = block.active_max_len;
        if (active_len > self.max_pos) self.max_pos = @min(active_len, 1000);

        // Surgical Loop: Process ONLY valid read count and bound by buffer capacity (1024)
        for (0..read_count) |i| {
            const len = @min(@as(usize, block.read_lengths[i]), 1000);
            for (0..len) |pos| {
                const q = block.qualities[pos][i];
                const phred = @min(@as(usize, q), 40);
                self.quality_counts[pos][phred] += 1;
            }
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}

    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        const self: *PerbasequalityStage = @ptrCast(@alignCast(ptr));
        try writer.print("\"quality_dist\": {{\"max_pos\": {d}, \"data\": [", .{self.max_pos});
        const limit = @min(self.max_pos, 1000);
        for (0..limit) |i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("[");
            for (self.quality_counts[i], 0..) |count, phred| {
                if (phred > 0) try writer.writeAll(",");
                try writer.print("{d}", .{count});
            }
            try writer.writeAll("]");
        }
        try writer.writeAll("]}");
    }

    pub fn stage(self: *PerbasequalityStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *PerbasequalityStage = @ptrCast(@alignCast(ctx));
                s.deinit(allocator);
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .per_base_quality, &.{
            .processBitplanes = PerbasequalityStage.processBitplanes,
            .finalize = PerbasequalityStage.finalize,
            .reportJson = PerbasequalityStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
