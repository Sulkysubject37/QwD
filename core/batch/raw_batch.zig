const std = @import("std");

pub const RawRead = struct {
    seq: []const u8,
    qual: []const u8,
};

pub const RawBatch = struct {
    reads: []RawRead,
    count: usize,
    capacity: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !RawBatch {
        return RawBatch{
            .reads = try allocator.alloc(RawRead, capacity),
            .count = 0,
            .capacity = capacity,
        };
    }

    pub fn deinit(self: *RawBatch, allocator: std.mem.Allocator) void {
        allocator.free(self.reads);
    }

    pub fn clear(self: *RawBatch) void {
        self.count = 0;
    }

    pub fn add(self: *RawBatch, seq: []const u8, qual: []const u8) bool {
        if (self.count >= self.capacity) return false;
        self.reads[self.count] = .{ .seq = seq, .qual = qual };
        self.count += 1;
        return true;
    }
};
