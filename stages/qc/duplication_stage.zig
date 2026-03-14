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
            // 2MB bloom filter
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

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        
        var seq_to_hash = read.seq;
        if (self.fast_mode and seq_to_hash.len > 50) {
            seq_to_hash = seq_to_hash[0..50];
        }

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
                v.key_ptr.* = try self.allocator.dupe(u8, seq_to_hash);
            } else {
                self.duplicate_reads += 1;
            }
        } else {
            if (self.map.contains(seq_to_hash)) {
                self.duplicate_reads += 1;
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
        
        const prev_total = self.total_reads;
        const prev_dups = self.duplicate_reads;
        
        self.total_reads += other.total_reads;
        // Internal duplicates in the other thread are always duplicates in the global stream
        self.duplicate_reads += other.duplicate_reads;

        if (self.fast_mode and self.bloom != null and other.bloom != null) {
            // Note: Merging Bloom filters is fast but might increase false positives
            // But we already added other.duplicate_reads. 
            // We only need to find duplicates BETWEEN self and other.
            // This is hard with Bloom filters without double counting.
            // For extreme speed, we accept some approximation error in --fast mode.
            self.bloom.?.merge(&other.bloom.?);
            return;
        }

        var it = other.map.keyIterator();
        while (it.next()) |key_ptr| {
            if (self.map.contains(key_ptr.*)) {
                self.duplicate_reads += 1;
            } else if (self.map.count() < 200000) {
                const res = try self.map.getOrPut(key_ptr.*);
                if (!res.found_existing) {
                    res.key_ptr.* = try self.allocator.dupe(u8, key_ptr.*);
                }
            }
        }
        _ = prev_total;
        _ = prev_dups;
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
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
