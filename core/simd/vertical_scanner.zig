const std = @import("std");

pub const FastqScanner = struct {
    pub const ScanResult = struct {
        indices: []usize,
        count: usize,
    };

    /// SIMD-accelerated newline scanner using platform-optimized indexOfScalar.
    pub fn scanNewlinesSIMD(chunk: []const u8, out: *ScanResult) void {
        out.count = 0;
        var i: usize = 0;
        while (std.mem.indexOfScalarPos(u8, chunk, i, '\n')) |idx| {
            if (out.count < out.indices.len) {
                out.indices[out.count] = idx;
                out.count += 1;
                i = idx + 1;
            } else break;
        }
    }
};
