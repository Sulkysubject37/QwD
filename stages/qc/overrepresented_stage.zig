const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const mode_mod = @import("mode");

pub const OverrepresentedStage = struct {
    map: std.StringHashMap(u64),
    allocator: std.mem.Allocator,
    total_reads: usize = 0,
    mode: mode_mod.Mode = .EXACT,

    pub fn init(allocator: std.mem.Allocator) !*OverrepresentedStage {
        const self = try allocator.create(OverrepresentedStage);
        self.* = .{
            .map = std.StringHashMap(u64).init(allocator),
            .allocator = allocator,
        };
        return self;
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
        
        if (self.mode == .APPROX and self.total_reads > 50_000) return true;

        if (self.mode == .EXACT or self.map.count() < 100000) {
            if (self.map.getPtr(read.seq)) |v| {
                v.* += 1;
            } else {
                const duped_seq = try self.allocator.dupe(u8, read.seq);
                errdefer self.allocator.free(duped_seq);
                const v = self.map.getOrPut(duped_seq) catch {
                    self.allocator.free(duped_seq);
                    return true; // Skip on OOM
                };
                if (v.found_existing) {
                    self.allocator.free(duped_seq);
                    v.value_ptr.* += 1;
                } else {
                    v.value_ptr.* = 1;
                }
            }
        } else {
            if (self.map.getPtr(read.seq)) |v| {
                v.* += 1;
            }
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
            if (self.mode == .APPROX and self.total_reads > 50_000) continue;

            const len = block.read_lengths[read_idx];
            for (0..len) |i| seq_buf[i] = block.bases[i][read_idx];
            const seq = seq_buf[0..len];

            if (self.mode == .EXACT or self.map.count() < 100000) {
                if (self.map.getPtr(seq)) |v| {
                    v.* += 1;
                } else {
                    const duped_seq = self.allocator.dupe(u8, seq) catch continue;
                    const v = self.map.getOrPut(duped_seq) catch {
                        self.allocator.free(duped_seq);
                        continue;
                    };
                    if (v.found_existing) {
                        self.allocator.free(duped_seq);
                        v.value_ptr.* += 1;
                    } else {
                        v.value_ptr.* = 1;
                    }
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
            if (self.mode == .APPROX and self.total_reads > 50_000) continue;

            if (self.mode == .EXACT or self.map.count() < 100000) {
                if (self.map.getPtr(read.seq)) |v| {
                    v.* += 1;
                } else {
                    const duped_seq = self.allocator.dupe(u8, read.seq) catch continue;
                    const v = self.map.getOrPut(duped_seq) catch {
                        self.allocator.free(duped_seq);
                        continue;
                    };
                    if (v.found_existing) {
                        self.allocator.free(duped_seq);
                        v.value_ptr.* += 1;
                    } else {
                        v.value_ptr.* = 1;
                    }
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
            if (self.map.getPtr(entry.key_ptr.*)) |v| {
                v.* += entry.value_ptr.*;
            } else {
                const duped_seq = self.allocator.dupe(u8, entry.key_ptr.*) catch continue;
                const v = self.map.getOrPut(duped_seq) catch {
                    self.allocator.free(duped_seq);
                    continue;
                };
                if (v.found_existing) {
                    self.allocator.free(duped_seq);
                    v.value_ptr.* += entry.value_ptr.*;
                } else {
                    v.value_ptr.* = entry.value_ptr.*;
                }
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
            } else if (entry.value_ptr.* == top_count and top_count > 0) {
                // Deterministic tie-break using lexicographical order
                if (std.mem.lessThan(u8, entry.key_ptr.*, top_seq)) {
                    top_seq = entry.key_ptr.*;
                }
            }
        }
        if (top_count > 1) {
            writer.print("  Most frequent: {s} (count={d})\n", .{ top_seq, top_count }) catch {};
        }
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        var top_seq: []const u8 = "";
        var top_count: u64 = 0;
        var it = self.map.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > top_count) {
                top_count = entry.value_ptr.*;
                top_seq = entry.key_ptr.*;
            } else if (entry.value_ptr.* == top_count and top_count > 0) {
                if (std.mem.lessThan(u8, entry.key_ptr.*, top_seq)) {
                    top_seq = entry.key_ptr.*;
                }
            }
        }
        
        try writer.print("\"overrepresented\": {{\"unique_sequences\": {d}, \"most_frequent\": \"", .{self.map.count()});
        try @import("structured_output").writeJsonEscaped(writer, top_seq);
        try writer.print("\", \"most_frequent_count\": {d}}}", .{top_count});
    }

    pub fn stage(self: *const @This()) stage_mod.Stage {
        return .{
            .ptr = @constCast(self),
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
