const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const OverrepresentedStage = struct {
    map: std.StringHashMap(u64),
    allocator: std.mem.Allocator,
    total_reads: usize = 0,
    fast_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator, fast_mode: bool) OverrepresentedStage {
        return OverrepresentedStage{
            .map = std.StringHashMap(u64).init(allocator),
            .allocator = allocator,
            .fast_mode = fast_mode,
        };
    }

    pub fn deinit(self: *OverrepresentedStage) void {
        var it = self.map.keyIterator();
        while (it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.map.deinit();
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        
        if (self.fast_mode and self.total_reads > 50_000) return true;

        if (self.map.count() < 100000) {
            const v = try self.map.getOrPut(read.seq);
            if (!v.found_existing) {
                v.key_ptr.* = try self.allocator.dupe(u8, read.seq);
                v.value_ptr.* = 1;
            } else {
                v.value_ptr.* += 1;
            }
        } else {
            if (self.map.getPtr(read.seq)) |v| {
                v.* += 1;
            }
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
            if (self.fast_mode and self.total_reads > 50_000) continue;

            const len = block.read_lengths[read_idx];
            for (0..len) |i| seq_buf[i] = block.bases[i][read_idx];
            const seq = seq_buf[0..len];

            if (self.map.count() < 100000) {
                const v = try self.map.getOrPut(seq);
                if (!v.found_existing) {
                    v.key_ptr.* = try self.allocator.dupe(u8, seq);
                    v.value_ptr.* = 1;
                } else {
                    v.value_ptr.* += 1;
                }
            } else {
                if (self.map.getPtr(seq)) |v| {
                    v.* += 1;
                }
            }
        }
        return true;
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (reads) |read| {
            self.total_reads += 1;
            if (self.fast_mode and self.total_reads > 50_000) continue;

            if (self.map.count() < 100000) {
                const v = try self.map.getOrPut(read.seq);
                if (!v.found_existing) {
                    v.key_ptr.* = try self.allocator.dupe(u8, read.seq);
                    v.value_ptr.* = 1;
                } else {
                    v.value_ptr.* += 1;
                }
            } else {
                if (self.map.getPtr(read.seq)) |v| {
                    v.* += 1;
                }
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
        
        var it = other.map.iterator();
        while (it.next()) |entry| {
            const res = try self.map.getOrPut(entry.key_ptr.*);
            if (!res.found_existing) {
                res.key_ptr.* = try self.allocator.dupe(u8, entry.key_ptr.*);
                res.value_ptr.* = entry.value_ptr.*;
            } else {
                res.value_ptr.* += entry.value_ptr.*;
            }
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Overrepresented Sequences Report:\n", .{}) catch {};
        writer.print("  Unique sequences: {d}\n", .{self.map.count()}) catch {};
        
        var top_seq: []const u8 = "";
        var top_count: u64 = 0;
        var it = self.map.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > top_count) {
                top_count = entry.value_ptr.*;
                top_seq = entry.key_ptr.*;
            }
        }
        if (top_count > 1) {
            writer.print("  Most frequent: {s} (count={d})\n", .{ top_seq, top_count }) catch {};
        }
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
