const std = @import("std");

pub const FastqColumnBlock = struct {
    // bases[pos][read_index]
    bases: [][]u8,
    // qualities[pos][read_index]
    qualities: [][]u8,
    read_lengths: []u16,
    read_count: usize,
    max_read_len: usize,
    capacity: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, max_read_len: usize) !FastqColumnBlock {
        var bases = try allocator.alloc([]u8, max_read_len);
        var qualities = try allocator.alloc([]u8, max_read_len);
        
        for (0..max_read_len) |i| {
            bases[i] = try allocator.alloc(u8, capacity);
            qualities[i] = try allocator.alloc(u8, capacity);
            @memset(bases[i], 0);
            @memset(qualities[i], 0);
        }

        return FastqColumnBlock{
            .bases = bases,
            .qualities = qualities,
            .read_lengths = try allocator.alloc(u16, capacity),
            .read_count = 0,
            .max_read_len = max_read_len,
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqColumnBlock) void {
        for (0..self.max_read_len) |i| {
            self.allocator.free(self.bases[i]);
            self.allocator.free(self.qualities[i]);
        }
        self.allocator.free(self.bases);
        self.allocator.free(self.qualities);
        self.allocator.free(self.read_lengths);
    }

    pub fn clear(self: *FastqColumnBlock) void {
        self.read_count = 0;
    }

    pub fn addRead(self: *FastqColumnBlock, seq: []const u8, qual: []const u8) bool {
        if (self.read_count >= self.capacity) return false;
        
        const len = @min(seq.len, self.max_read_len);
        for (0..len) |i| {
            self.bases[i][self.read_count] = seq[i];
            self.qualities[i][self.read_count] = qual[i];
        }
        // Zero out the rest of the column for this read index if it's shorter than max_read_len
        // but for speed we might just rely on read_lengths
        self.read_lengths[self.read_count] = @intCast(len);
        self.read_count += 1;
        return true;
    }
};
