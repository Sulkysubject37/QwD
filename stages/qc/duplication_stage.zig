const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const DuplicationStage = struct {
    map: std.StringHashMap(void),
    allocator: std.mem.Allocator,
    total_reads: usize = 0,
    duplicate_reads: usize = 0,
    fast_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator, fast_mode: bool) DuplicationStage {
        return DuplicationStage{
            .map = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
            .fast_mode = fast_mode,
        };
    }

    pub fn deinit(self: *DuplicationStage) void {
        var it = self.map.keyIterator();
        while (it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.map.deinit();
    }

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        
        // Fast mode: only hash first 50bp
        var seq_to_hash = read.seq;
        if (self.fast_mode and seq_to_hash.len > 50) {
            seq_to_hash = seq_to_hash[0..50];
        }
        
        // Track up to 200,000 to keep it bounded
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
        self.total_reads += other.total_reads;
        
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
        // Note: other.duplicate_reads also need to be merged?
        // Actually, other.duplicate_reads are duplicates found WITHIN that thread's stream.
        self.duplicate_reads += other.duplicate_reads;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.fast_mode) {
            writer.print("Duplication Rate Report (Fast Mode / Approximate):\n", .{}) catch {};
        } else {
            writer.print("Duplication Rate Report:\n", .{}) catch {};
        }
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
