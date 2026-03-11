const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const OverrepresentedStage = struct {
    // A bounded map to track most frequent sequences
    // Using string hash map, bounded size
    map: std.StringHashMap(u64),
    allocator: std.mem.Allocator,
    total_reads: usize = 0,

    pub fn init(allocator: std.mem.Allocator) OverrepresentedStage {
        return OverrepresentedStage{
            .map = std.StringHashMap(u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OverrepresentedStage) void {
        var it = self.map.keyIterator();
        while (it.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.map.deinit();
    }

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        
        // We only track up to 100,000 distinct sequences to prevent unbounded memory growth
        if (self.map.count() < 100000) {
            const v = try self.map.getOrPut(read.seq);
            if (!v.found_existing) {
                // Must duplicate the string since the read buffer will be overwritten
                v.key_ptr.* = try self.allocator.dupe(u8, read.seq);
                v.value_ptr.* = 1;
            } else {
                v.value_ptr.* += 1;
            }
        } else {
            // If already full, just update existing ones
            if (self.map.getPtr(read.seq)) |v| {
                v.* += 1;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Overrepresented Sequences Report:\n", .{}) catch {};
        writer.print("  Total unique sequences tracked: {d}\n", .{self.map.count()}) catch {};
        
        // Find top sequence
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
            writer.print("  Most frequent sequence (count={d}): {s}\n", .{ top_count, top_seq }) catch {};
        }
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
            },
        };
    }
};
