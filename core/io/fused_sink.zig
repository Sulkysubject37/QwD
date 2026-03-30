const std = @import("std");

/// FusedSink: A high-performance sink that maps ASCII symbols to 2-bit DNA 
/// encoding and writes directly into columnar Bitplane structures.
pub const FusedSink = struct {
    // Current bitplane lanes (8 lanes for sequence and quality)
    lanes: *[8]u32,
    // Current bit position in the 32-bit columnar chunk
    pos: *usize,
    
    // Track if we are in sequence or quality mode
    is_seq: bool = true,

    pub fn init(lanes: *[8]u32, pos: *usize) FusedSink {
        return .{
            .lanes = lanes,
            .pos = pos,
        };
    }

    pub inline fn emit(self: *FusedSink, symbol: u8) !void {
        if (self.pos.* >= 32) return error.BitplaneChunkFull;

        if (self.is_seq) {
            // Map ASCII to 2-bit DNA during decompression
            const encoded: u8 = switch (symbol) {
                'A', 'a' => 0b00,
                'C', 'c' => 0b01,
                'G', 'g' => 0b10,
                'T', 't' => 0b11,
                else => 0b00, // Handle N/Metadata separately
            };
            
            self.lanes[0] |= (@as(u32, encoded & 1) << @intCast(self.pos.*));
            self.lanes[1] |= (@as(u32, (encoded >> 1) & 1) << @intCast(self.pos.*));
        } else {
            // Map ASCII Qual to 8-bit bitplanes
            inline for (0..8) |i| {
                const bit = (symbol >> i) & 1;
                self.lanes[i] |= (@as(u32, bit) << @intCast(self.pos.*));
            }
        }
        
        // Note: In a real implementation, we'd handle record boundaries 
        // ('\n', '@', '+') to switch between is_seq states.
    }
};
