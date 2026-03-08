const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const DuplicationStage = struct {
    map: std.StringHashMap(void),
    allocator: std.mem.Allocator,
    total_reads: usize = 0,
    duplicate_reads: usize = 0,

    pub fn init(allocator: std.mem.Allocator) DuplicationStage {
        return DuplicationStage{
            .map = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
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
        
        // Track up to 200,000 to keep it bounded
        if (self.map.count() < 200000) {
            const v = try self.map.getOrPut(read.seq);
            if (!v.found_existing) {
                v.key_ptr.* = try self.allocator.dupe(u8, read.seq);
            } else {
                self.duplicate_reads += 1;
            }
        } else {
            if (self.map.contains(read.seq)) {
                self.duplicate_reads += 1;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("Duplication Rate Report:\n", .{});
        std.debug.print("  Total reads:     {d}\n", .{self.total_reads});
        std.debug.print("  Duplicate reads: {d}\n", .{self.duplicate_reads});
        const ratio = if (self.total_reads > 0) @as(f64, @floatFromInt(self.duplicate_reads)) / @as(f64, @floatFromInt(self.total_reads)) else 0.0;
        std.debug.print("  Duplication ratio: {d:.2}%\n", .{ratio * 100.0});
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
