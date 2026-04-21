const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const mode_mod = @import("mode");

const bitplanes = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const OverrepresentedStage = struct {
    counts: std.AutoHashMap(u64, usize),
    hashes_to_seqs: std.AutoHashMap(u64, []const u8),
    allocator: std.mem.Allocator,
    total_reads: usize = 0,
    mode: mode_mod.Mode = .exact,

    pub fn init(allocator: std.mem.Allocator, mode: mode_mod.Mode) OverrepresentedStage {
        return .{
            .counts = std.AutoHashMap(u64, usize).init(allocator),
            .hashes_to_seqs = std.AutoHashMap(u64, []const u8).init(allocator),
            .allocator = allocator,
            .mode = mode,
        };
    }

    pub fn deinit(self: *OverrepresentedStage) void {
        var it = self.hashes_to_seqs.valueIterator();
        while (it.next()) |seq| {
            self.allocator.free(seq.*);
        }
        self.hashes_to_seqs.deinit();
        self.counts.deinit();
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        
        // APPROX MODE: Sampling & Memory Capping
        if (self.mode == .fast) {
            if (self.total_reads % 10 != 0) return true; // 10% sampling
            if (self.counts.count() > 10000) return true; // Hard memory floor
        }

        const hash = std.hash.Wyhash.hash(0, read.seq);
        const entry = try self.counts.getOrPut(hash);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
            if (self.hashes_to_seqs.count() < 500) {
                const seq_copy = try self.allocator.dupe(u8, read.seq);
                try self.hashes_to_seqs.put(hash, seq_copy);
            }
        }
        entry.value_ptr.* += 1;
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const count = block.read_count;
        
        const u64_count = (count + 63) / 64;
        for (0..u64_count) |word_idx| {
            // APPROX MODE: Word-level sampling
            if (self.mode == .fast and word_idx % 4 != 0) continue;

            for (0..64) |bit_idx| {
                const read_idx = word_idx * 64 + bit_idx;
                if (read_idx >= count) break;
                self.total_reads += 1;

                const len = block.read_lengths[read_idx];
                const hash = bp.computeSignature(read_idx, len);
                
                if (self.mode == .fast and self.counts.count() > 10000) continue;

                const entry = try self.counts.getOrPut(hash);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                    if (self.hashes_to_seqs.count() < 500) {
                        const read_seq = block.getReadRaw(read_idx, self.allocator);
                        try self.hashes_to_seqs.put(hash, read_seq.seq);
                        self.allocator.free(read_seq.qual);
                    }
                }
                entry.value_ptr.* += 1;
            }
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}

    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        
        var most_frequent_hash: u64 = 0;
        var max_count: usize = 0;
        var it = self.counts.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > max_count) {
                max_count = entry.value_ptr.*;
                most_frequent_hash = entry.key_ptr.*;
            }
        }

        const most_frequent_seq = if (self.hashes_to_seqs.get(most_frequent_hash)) |s| s else "None";
        
        const multiplier: usize = if (self.mode == .fast) 4 else 1;
        try writer.print("\"overrepresented\": {{\"unique_sequences\": {d}, \"most_frequent\": \"{s}\", \"most_frequent_count\": {d}}}", .{
            self.counts.count(), most_frequent_seq, max_count * multiplier,
        }); 
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;

        var it = other.counts.iterator();
        while (it.next()) |entry| {
            const hash = entry.key_ptr.*;
            const count = entry.value_ptr.*;
            
            if (self.mode == .fast and self.counts.count() > 10000) break;

            const res = try self.counts.getOrPut(hash);
            if (!res.found_existing) {
                res.value_ptr.* = 0;
                if (other.hashes_to_seqs.get(hash)) |other_seq| {
                    if (self.hashes_to_seqs.count() < 500) {
                        const seq_copy = try self.allocator.dupe(u8, other_seq);
                        try self.hashes_to_seqs.put(hash, seq_copy);
                    }
                }
            }
            res.value_ptr.* += count;
        }
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(OverrepresentedStage);
        new_self.* = OverrepresentedStage.init(allocator, self.mode);
        return new_self;
    }

    pub fn stage(self: *OverrepresentedStage) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = OverrepresentedStage.process,
    .finalize = OverrepresentedStage.finalize,
    .report = OverrepresentedStage.report,
    .reportJson = OverrepresentedStage.reportJson,
    .merge = OverrepresentedStage.merge,
    .clone = OverrepresentedStage.clone,
    .processBitplanes = OverrepresentedStage.processBitplanes,
};
