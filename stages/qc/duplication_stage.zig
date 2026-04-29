const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bloom_filter = @import("bloom_filter");
const mode_mod = @import("mode");

const bitplanes = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const DuplicationStage = struct {
    total_reads: usize = 0,
    duplicate_count: usize = 0,
    mode: mode_mod.Mode = .exact,
    
    // Fast Mode: Bloom Filter
    bloom: ?bloom_filter.BloomFilter = null,
    
    // Exact Mode: Definitive HashMap
    exact_map: ?std.AutoHashMap(u64, void) = null,
    
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, mode: mode_mod.Mode) DuplicationStage {
        var self = DuplicationStage{
            .allocator = allocator,
            .mode = mode,
        };
        if (mode == .fast) {
            self.bloom = bloom_filter.BloomFilter.init(allocator, 8 * 1024 * 1024) catch null;
        } else {
            self.exact_map = std.AutoHashMap(u64, void).init(allocator);
        }
        return self;
    }

    pub fn deinit(self: *DuplicationStage) void {
        if (self.bloom) |*b| b.deinit(self.allocator);
        if (self.exact_map) |*m| m.deinit();
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const count = block.read_count;
        self.total_reads += count;

        for (0..count) |i| {
            const len = block.read_lengths[i];
            const sig = bp.computeSignature(i, len);
            
            if (self.mode == .fast) {
                if (self.bloom) |*b| {
                    const sig_bytes = std.mem.asBytes(&sig);
                    if (b.contains(sig_bytes)) {
                        self.duplicate_count += 1;
                    } else {
                        b.add(sig_bytes);
                    }
                }
            } else {
                if (self.exact_map) |*m| {
                    const res = try m.getOrPut(sig);
                    if (res.found_existing) {
                        self.duplicate_count += 1;
                    }
                }
            }
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const ratio: f64 = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_count)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        try writer.print("\"duplication\": {{\"total_reads\": {d}, \"duplicate_reads\": {d}, \"duplication_ratio\": {d:.4}}}", .{
            self.total_reads,
            self.duplicate_count,
            ratio,
        });
    }

    pub fn stage(self: *DuplicationStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *DuplicationStage = @ptrCast(@alignCast(ctx));
                s.deinit();
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .duplication, &.{
            .processBitplanes = DuplicationStage.processBitplanes,
            .finalize = DuplicationStage.finalize,
            .reportJson = DuplicationStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
