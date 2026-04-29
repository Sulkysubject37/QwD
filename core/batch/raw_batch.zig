const std = @import("std");

pub const RawRead = struct {
    seq: []const u8,
    qual: []const u8,
};

pub const RawBatch = struct {
    reads: []RawRead,
    count: usize,
    capacity: usize,
    
    // Owned buffer for zero-drop precision and stability
    buffer: []u8,
    buf_pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !RawBatch {
        return RawBatch{
            .reads = try allocator.alloc(RawRead, capacity),
            .count = 0,
            .capacity = capacity,
            .buffer = try allocator.alloc(u8, capacity * 512), // 512 bytes per read
        };
    }

    pub fn deinit(self: *RawBatch, allocator: std.mem.Allocator) void {
        allocator.free(self.reads);
        allocator.free(self.buffer);
    }

    pub fn clear(self: *RawBatch) void {
        self.count = 0;
        self.buf_pos = 0;
    }

    pub fn add(self: *RawBatch, seq: []const u8, qual: []const u8) bool {
        if (self.count >= self.capacity) return false;
        
        const total_len = seq.len + qual.len;
        if (self.buf_pos + total_len > self.buffer.len) return false;

        // Copy data to owned buffer for stability across block boundaries
        const s_start = self.buf_pos;
        @memcpy(self.buffer[s_start .. s_start + seq.len], seq);
        self.buf_pos += seq.len;

        const q_start = self.buf_pos;
        @memcpy(self.buffer[q_start .. q_start + qual.len], qual);
        self.buf_pos += qual.len;

        self.reads[self.count] = .{
            .seq = self.buffer[s_start .. s_start + seq.len],
            .qual = self.buffer[q_start .. q_start + qual.len],
        };
        self.count += 1;
        return true;
    }
};
