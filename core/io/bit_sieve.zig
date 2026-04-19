const std = @import("std");
const builtin = @import("builtin");

pub const BitSieve = struct {
    bit_buffer: u64 = 0,
    bit_count: u8 = 0,
    inner_reader: *std.Io.Reader,

    pub fn init(reader: *std.Io.Reader) BitSieve {
        return .{
            .inner_reader = reader,
        };
    }

    pub fn refill(self: *BitSieve) !void {
        while (self.bit_count <= 56) {
            var byte: u8 = undefined;
            const n = self.inner_reader.readSliceShort(std.mem.asBytes(&byte)) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            if (n == 0) break;
            
            self.bit_buffer |= (@as(u64, byte) << @as(u6, @intCast(self.bit_count)));
            self.bit_count += 8;
        }
    }

    pub inline fn peekBits(self: *const BitSieve, comptime n: u6) u64 {
        const mask = (@as(u64, 1) << n) - 1;
        return self.bit_buffer & mask;
    }

    pub inline fn consume(self: *BitSieve, n: u6) void {
        self.bit_buffer >>= n;
        self.bit_count -= n;
    }

    pub inline fn readBits(self: *BitSieve, comptime n: u6) !u64 {
        if (self.bit_count < n) try self.refill();
        const val = self.peekBits(n);
        self.consume(n);
        return val;
    }

    pub fn readBitsRuntime(self: *BitSieve, n: u6) !u64 {
        if (n == 0) return 0;
        if (self.bit_count < n) try self.refill();
        const mask = (@as(u64, 1) << n) - 1;
        const val = self.bit_buffer & mask;
        self.consume(n);
        return val;
    }
    
    pub fn alignToByte(self: *BitSieve) void {
        const skip: u6 = @intCast(self.bit_count % 8);
        if (skip > 0) {
            self.consume(skip);
        }
    }
};
