const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bloom_mod = @import("bloom_filter");
const mode_mod = @import("mode");

pub const DuplicationStage = struct {
    map: std.StringHashMap(void),
    bloom: ?bloom_mod.BloomFilter = null,
    allocator: std.mem.Allocator,
    total_reads: usize = 0,
    duplicate_reads: usize = 0,
    mode: mode_mod.Mode = .EXACT,

    pub fn init(allocator: std.mem.Allocator, is_fast: bool) DuplicationStage {
        var self = DuplicationStage{
            .map = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
            .mode = if (is_fast) .APPROX else .EXACT,
        };
        if (self.mode == .APPROX) {
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
        if (self.mode == .APPROX and seq_to_hash.len > 50) seq_to_hash = seq_to_hash[0..50];

        if (self.mode == .APPROX and self.bloom != null) {
            if (self.bloom.?.contains(seq_to_hash)) {
                self.duplicate_reads += 1;
            } else {
                self.bloom.?.add(seq_to_hash);
            }
            return true;
        }

        if (self.mode == .EXACT or self.map.count() < 200000) {
            if (self.map.contains(seq_to_hash)) {
                self.duplicate_reads += 1;
            } else {
                const duped_seq = try self.allocator.dupe(u8, seq_to_hash);
                errdefer self.allocator.free(duped_seq);
                const v = try self.map.getOrPut(duped_seq);
                if (v.found_existing) {
                    self.allocator.free(duped_seq);
                    self.duplicate_reads += 1;
                } else {
                    v.value_ptr.* = {};
                }
            }
        } else {
            if (self.map.contains(seq_to_hash)) self.duplicate_reads += 1;
        }
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
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
            if (self.mode == .APPROX and seq.len > 50) seq = seq[0..50];

            if (self.mode == .APPROX and self.bloom != null) {


                if (self.bloom.?.contains(seq)) {
                    self.duplicate_reads += 1;
                } else {
                    self.bloom.?.add(seq);
                }
                continue;
            }


            if (self.mode == .EXACT or self.map.count() < 200000) {
                if (self.map.contains(seq)) {
                    self.duplicate_reads += 1;
                } else {
                    const duped_seq = self.allocator.dupe(u8, seq) catch continue;
                    const v = self.map.getOrPut(duped_seq) catch {
                        self.allocator.free(duped_seq);
                        continue;
                    };
                    if (v.found_existing) {
                        self.allocator.free(duped_seq);
                        self.duplicate_reads += 1;
                    } else {
                        v.value_ptr.* = {};
                    }
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
            if (self.mode == .APPROX and seq_to_hash.len > 50) seq_to_hash = seq_to_hash[0..50];

            if (self.mode == .APPROX and self.bloom != null) {

                if (self.bloom.?.contains(seq_to_hash)) {
                    self.duplicate_reads += 1;
                } else {
                    self.bloom.?.add(seq_to_hash);
                }
                continue;
            }

            if (self.mode == .EXACT or self.map.count() < 200000) {
                if (self.map.contains(seq_to_hash)) {
                    self.duplicate_reads += 1;
                } else {
                    const duped_seq = self.allocator.dupe(u8, seq_to_hash) catch continue;
                    const v = self.map.getOrPut(duped_seq) catch {
                        self.allocator.free(duped_seq);
                        continue;
                    };
                    if (v.found_existing) {
                        self.allocator.free(duped_seq);
                        self.duplicate_reads += 1;
                    } else {
                        v.value_ptr.* = {};
                    }
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
        
        var it = other.map.iterator();
        while (it.next()) |entry| {
            const seq = entry.key_ptr.*;
            if (self.map.contains(seq)) {
                // If it's already in our map, this sequence was the 'first' instance in both threads.
                // We must count it as a duplicate now.
                self.duplicate_reads += 1;
            } else {
                const duped = self.allocator.dupe(u8, seq) catch continue;
                const gop = self.map.getOrPut(duped) catch {
                    self.allocator.free(duped);
                    continue;
                };
                if (gop.found_existing) {
                    self.allocator.free(duped);
                    self.duplicate_reads += 1;
                } else {
                    gop.value_ptr.* = {};
                }
            }
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Duplication Rate Report:\n", .{}) catch {};
        writer.print("  Total reads:     {d}\n", .{self.total_reads}) catch {};
        writer.print("  Duplicate reads: {d}\n", .{self.duplicate_reads}) catch {};
        const ratio = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_reads)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        writer.print("  Duplication ratio: {d:.2}%\n", .{ratio * 100.0}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const ratio = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_reads)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        try writer.print(
            \\"duplication": {{
            \\  "total_reads": {d},
            \\  "duplicate_reads": {d},
            \\  "duplication_ratio": {d:.4}
            \\}}
        , .{ self.total_reads, self.duplicate_reads, ratio });
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
