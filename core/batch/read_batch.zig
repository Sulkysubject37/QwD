const std = @import("std");

pub const ReadMeta = struct {
    id_len: usize,
};

pub const ReadBatch = struct {
    sequences: [][]const u8,
    qualities: [][]const u8,
    metadata: []ReadMeta,
    count: usize,
    capacity: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ReadBatch {
        return ReadBatch{
            .sequences = try allocator.alloc([]const u8, capacity),
            .qualities = try allocator.alloc([]const u8, capacity),
            .metadata = try allocator.alloc(ReadMeta, capacity),
            .count = 0,
            .capacity = capacity,
        };
    }

    pub fn deinit(self: *ReadBatch, allocator: std.mem.Allocator) void {
        allocator.free(self.sequences);
        allocator.free(self.qualities);
        allocator.free(self.metadata);
    }

    pub fn clear(self: *ReadBatch) void {
        self.count = 0;
    }

    pub fn add(self: *ReadBatch, seq: []const u8, qual: []const u8, id_len: usize) bool {
        if (self.count >= self.capacity) return false;
        self.sequences[self.count] = seq;
        self.qualities[self.count] = qual;
        self.metadata[self.count] = .{ .id_len = id_len };
        self.count += 1;
        return true;
    }
};
