const std = @import("std");

pub const ReadMeta = struct {
    id_len: usize,
};

pub const ReadBatch = struct {
    sequences: [][]u8,
    qualities: [][]u8,
    metadata: []ReadMeta,
    // Buffer memory owned by this batch
    buffer: []u8,
    buffer_pos: usize = 0,
    count: usize,
    capacity: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ReadBatch {
        const sequences = try allocator.alloc([]u8, capacity);
        const qualities = try allocator.alloc([]u8, capacity);
        const metadata = try allocator.alloc(ReadMeta, capacity);
        // Average read length 200 * 2 (seq+qual) * capacity
        const buffer_size = capacity * 400; 
        const buffer = try allocator.alloc(u8, buffer_size);

        return ReadBatch{
            .sequences = sequences,
            .qualities = qualities,
            .metadata = metadata,
            .buffer = buffer,
            .count = 0,
            .capacity = capacity,
        };
    }

    pub fn deinit(self: *ReadBatch, allocator: std.mem.Allocator) void {
        allocator.free(self.sequences);
        allocator.free(self.qualities);
        allocator.free(self.metadata);
        allocator.free(self.buffer);
    }

    pub fn clear(self: *ReadBatch) void {
        self.count = 0;
        self.buffer_pos = 0;
    }

    pub fn add(self: *ReadBatch, seq: []const u8, qual: []const u8, id_len: usize) bool {
        if (self.count >= self.capacity) return false;
        
        const total_len = seq.len + qual.len;
        if (self.buffer_pos + total_len > self.buffer.len) return false;

        // Copy seq
        const seq_dest = self.buffer[self.buffer_pos .. self.buffer_pos + seq.len];
        std.mem.copyForwards(u8, seq_dest, seq);
        self.sequences[self.count] = seq_dest;
        self.buffer_pos += seq.len;

        // Copy qual
        const qual_dest = self.buffer[self.buffer_pos .. self.buffer_pos + qual.len];
        std.mem.copyForwards(u8, qual_dest, qual);
        self.qualities[self.count] = qual_dest;
        self.buffer_pos += qual.len;

        self.metadata[self.count] = .{ .id_len = id_len };
        self.count += 1;
        return true;
    }
};
