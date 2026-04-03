const std = @import("std");

/// Minimal BGZF (Blocked GNU Zip Format) encoder for testing.
/// Reads from stdin, writes compressed blocks to stdout.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    const block_size = 64 * 1024; // standard BGZF block size
    var buffer = try allocator.alloc(u8, block_size);
    defer allocator.free(buffer);
    
    const comp_buffer = try allocator.alloc(u8, block_size + 1024);
    defer allocator.free(comp_buffer);

    while (true) {
        const n = try stdin.readAll(buffer);
        if (n == 0) break;

        // 1. Gzip Header (10 bytes) + Extra Field (6 bytes)
        // [ID1, ID2, CM, FLG, MTIME(4), XFL, OS, XLEN(2), SI1, SI2, SLEN(2), BSIZE(2)]
        
        var header = [_]u8{0} ** 18;
        header[0] = 0x1f; header[1] = 0x8b; // ID
        header[2] = 8;    // CM = Deflate
        header[3] = 4;    // FLG = FEXTRA
        // MTIME = 0
        header[8] = 0;    // XFL
        header[9] = 255;  // OS = Unknown
        header[10] = 6;   // XLEN LSB
        header[11] = 0;   // XLEN MSB
        header[12] = 'B'; header[13] = 'C'; // SI
        header[14] = 2;   // SLEN LSB
        header[15] = 0;   // SLEN MSB
        
        // We will fill BSIZE later

        // 2. Compress payload
        var input_stream = std.io.fixedBufferStream(buffer[0..n]);
        var fbs = std.io.fixedBufferStream(comp_buffer);
        try std.compress.flate.deflate.compress(.raw, input_stream.reader(), fbs.writer(), .{ .level = .fast });
        const compressed_payload = fbs.getWritten();

        // 3. CRC32 and ISIZE
        var crc = std.hash.Crc32.init();
        crc.update(buffer[0..n]);
        const checksum = crc.final();
        const input_size = @as(u32, @intCast(n));

        // 4. Calculate total block size (BSIZE = total_len - 1)
        const total_len = 18 + compressed_payload.len + 8;
        const bsize = @as(u16, @intCast(total_len - 1));
        header[16] = @as(u8, @intCast(bsize & 0xFF));
        header[17] = @as(u8, @intCast(bsize >> 8));

        // 5. Write Block
        try stdout.writeAll(&header);
        try stdout.writeAll(compressed_payload);
        try stdout.writeInt(u32, checksum, .little);
        try stdout.writeInt(u32, input_size, .little);
    }

    // Write empty EOF block (standard BGZF requirement)
    try stdout.writeAll("\x1f\x8b\x08\x04\x00\x00\x00\x00\x00\xff\x06\x00\x42\x43\x02\x00\x1b\x00\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00");
}
