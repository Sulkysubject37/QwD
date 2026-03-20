const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bloom_mod = @import("bloom_filter");

pub const DuplicationStage = struct {
    map: std.StringHashMap(void),
    bloom: ?bloom_mod.BloomFilter = null,
    allocator: std.mem.Allocator,
    total_reads: usize = 0,
    duplicate_reads: usize = 0,
    fast_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator, fast_mode: bool) DuplicationStage {
        var self = DuplicationStage{
            .map = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
            .fast_mode = fast_mode,
        };
        if (fast_mode) {
            self.bloom = bloom_mod.BloomFilter.init(allocator, 2 * 1024 * 1024) catch null;
        }
        return self;
    }

    pub fn deinit(self: *DuplicationStage) void {
        var it = self.map.keyIterator();
        while (it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.map.deinit();
        if (self.bloom) |*b| {
            b.deinit(self.allocator);
        }
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        var seq_to_hash = read.seq;
        if (self.fast_mode and seq_to_hash.len > 50) seq_to_hash = seq_to_hash[0..50];

        if (self.fast_mode and self.bloom != null) {
            if (self.bloom.?.contains(seq_to_hash)) {
                self.duplicate_reads += 1;
            } else {
                self.bloom.?.add(seq_to_hash);
            }
            return true;
        }

        if (self.map.count() < 200000) {
            const v = try self.map.getOrPut(seq_to_hash);
            if (!v.found_existing) {
                const key = try self.allocator.dupe(u8, seq_to_hash);
                v.key_ptr.* = key;
                v.value_ptr.* = {};
            } else {
                self.duplicate_reads += 1;
            }
        } else {
            if (self.map.contains(seq_to_hash)) self.duplicate_reads += 1;
        }
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").Bitplanes, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        _ = bp;
        return processBlock(ptr, block);
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        var seq_buf: [1024]u8 = undefined;

        for (0..block.read_count) |read_idx| {
            self.total_reads += 1;
            const len = block.read_lengths[read_idx];
            for (0..len) |i| seq_buf[i] = block.bases[i][read_idx];
            var seq = seq_buf[0..len];
            if (self.fast_mode and seq.len > 50) seq = seq[0..50];

            if (self.fast_mode and self.bloom != null) {
                if (self.bloom.?.contains(seq)) {
                    self.duplicate_reads += 1;
                } else {
                    self.bloom.?.add(seq);
                }
                continue;
            }

            if (self.map.count() < 200000) {
                const v = try self.map.getOrPut(seq);
                if (!v.found_existing) {
                    const key = try self.allocator.dupe(u8, seq);
                    v.key_ptr.* = key;
                    v.value_ptr.* = {};
                } else {
                    self.duplicate_reads += 1;
                }
            } else {
                if (self.map.contains(seq)) self.duplicate_reads += 1;
            }
        }
        return true;
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (reads) |read| {
            self.total_reads += 1;
            var seq_to_hash = read.seq;
            if (self.fast_mode and seq_to_hash.len > 50) seq_to_hash = seq_to_hash[0..50];

            if (self.fast_mode and self.bloom != null) {
                if (self.bloom.?.contains(seq_to_hash)) {
                    self.duplicate_reads += 1;
                } else {
                    self.bloom.?.add(seq_to_hash);
                }
                continue;
            }

            if (self.map.count() < 200000) {
                const v = try self.map.getOrPut(seq_to_hash);
                if (!v.found_existing) {
                    const key = try self.allocator.dupe(u8, seq_to_hash);
                    v.key_ptr.* = key;
                    v.value_ptr.* = {};
                } else {
                    self.duplicate_reads += 1;
                }
            } else {
                if (self.map.contains(seq_to_hash)) self.duplicate_reads += 1;
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
        self.total_reads += other.total_reads;
        self.duplicate_reads += other.duplicate_reads;
        // Skip map merging for speed in this phase
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Duplication Rate Report:\n", .{}) catch {};
        writer.print("  Total reads:     {d}\n", .{self.total_reads}) catch {};
        writer.print("  Duplicate reads: {d}\n", .{self.duplicate_reads}) catch {};
        const ratio = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_reads)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        writer.print("  Duplication ratio: {d:.2}%\n", .{ratio * 100.0}) catch {};
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
                .merge = merge,
            },
        };
    }
};
