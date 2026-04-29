const std = @import("std");

pub const Lz77Engine = struct {
    // Standard DEFLATE window size
    window: [32768]u8 = undefined,
    pos: usize = 0,

    pub fn init() Lz77Engine {
        var self = Lz77Engine{};
        @memset(&self.window, 0);
        return self;
    }

    pub inline fn appendByte(self: *Lz77Engine, byte: u8) void {
        self.window[self.pos] = byte;
        self.pos = (self.pos + 1) & 0x7FFF;
    }

    /// Optimized match copy.
    pub fn copyMatch(self: *Lz77Engine, distance: u16, length: u16, sink: anytype) !void {
        var len = length;
        // Correct distance logic: start_pos is 'distance' bytes BEHIND current 'pos'
        var src_pos = (@as(isize, @intCast(self.pos)) - @as(isize, @intCast(distance))) & 0x7FFF;

        while (len > 0) {
            const byte = self.window[@as(usize, @intCast(src_pos))];
            try sink.emit(byte);
            self.appendByte(byte);
            src_pos = (src_pos + 1) & 0x7FFF;
            len -= 1;
        }
    }
};
