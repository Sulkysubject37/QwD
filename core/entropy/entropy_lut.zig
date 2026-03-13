const std = @import("std");

pub const EntropyLUT = struct {
    table: [1024]f64,
    
    pub fn init() EntropyLUT {
        var lut = EntropyLUT{ .table = [_]f64{0.0} ** 1024 };
        for (1..1024) |i| {
            const f = @as(f64, @floatFromInt(i));
            lut.table[i] = f * std.math.log2(f);
        }
        return lut;
    }
    
    pub fn getEntropy(self: *const EntropyLUT, counts: [4]usize, len: usize) f64 {
        if (len == 0 or len >= 1024) return 0.0;
        var sum: f64 = 0.0;
        for (counts) |c| {
            if (c > 0 and c < 1024) {
                sum += self.table[c];
            }
        }
        return (self.table[len] - sum) / @as(f64, @floatFromInt(len));
    }
};

pub var global_lut: EntropyLUT = undefined;

pub fn initGlobal() void {
    global_lut = EntropyLUT.init();
}
