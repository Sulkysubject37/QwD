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

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        
        const hash = std.hash.Wyhash.hash(0, read.seq);
        
        if (self.mode == .fast) {
            if (self.bloom) |*b| {
                const h_bytes = std.mem.asBytes(&hash);
                if (b.contains(h_bytes)) {
                    self.duplicate_count += 1;
                } else {
                    b.add(h_bytes);
                }
            }
        } else {
            if (self.exact_map) |*m| {
                const res = try m.getOrPut(hash);
                if (res.found_existing) {
                    self.duplicate_count += 1;
                }
            }
        }
        return true;
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
    
    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const ratio: f64 = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_count)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        writer.print("Duplication: {d}/{d} ({d:.2}%)\n", .{self.duplicate_count, self.total_reads, ratio * 100.0}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const ratio: f64 = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_count)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        try writer.print("\"duplication\": {{\"total_reads\": {d}, \"duplicate_reads\": {d}, \"duplication_ratio\": {d:.4}}}", .{
            self.total_reads,
            self.duplicate_count,
            ratio,
        });
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.duplicate_count += other.duplicate_count;
        
        if (self.mode == .fast) {
            if (self.bloom != null and other.bloom != null) {
                self.bloom.?.merge(&other.bloom.?);
            }
        } else {
            if (self.exact_map) |*m| {
                var it = other.exact_map.?.keyIterator();
                while (it.next()) |k| {
                    _ = try m.getOrPut(k.*);
                }
            }
        }
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(DuplicationStage);
        new_self.* = DuplicationStage.init(allocator, self.mode);
        return new_self;
    }

    pub fn stage(self: *DuplicationStage) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = DuplicationStage.process,
    .finalize = DuplicationStage.finalize,
    .report = DuplicationStage.report,
    .reportJson = DuplicationStage.reportJson,
    .merge = DuplicationStage.merge,
    .clone = DuplicationStage.clone,
    .processBitplanes = DuplicationStage.processBitplanes,
};
