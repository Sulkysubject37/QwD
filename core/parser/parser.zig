const std = @import("std");

/// A single sequencing read.
/// All fields are slices referencing buffer memory to avoid copying.
pub const Read = struct {
    id: []const u8,
    seq: []const u8,
    qual: []const u8,

    /// Validates that the sequence and quality strings have the same length.
    pub fn validate(self: Read) bool {
        return self.seq.len == self.qual.len;
    }
};

pub const ParserError = error{
    InvalidFormat,
    IncompleteRecord,
    MismatchedSequenceQuality,
    StreamError,
};

pub const FastqParser = struct {
    reader: std.io.AnyReader,
    buffer: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize) !FastqParser {
        const buffer = try allocator.alloc(u8, buffer_size);
        return FastqParser{
            .reader = reader,
            .buffer = buffer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqParser) void {
        self.allocator.free(self.buffer);
    }

    /// Parses the next FASTQ record from the stream.
    /// Returns a Read object pointing into internal buffers or an error.
    /// Note: This simple implementation assumes a record fits within the buffer
    /// and lines are correctly terminated. For Phase Z, we focus on clarity.
    pub fn next(self: *FastqParser, out_buffer: []u8) !?Read {
        // Line 1: @ID
        const id_line = (try self.reader.readUntilDelimiterOrEof(out_buffer, '\n')) orelse return null;
        if (id_line.len == 0 or id_line[0] != '@') return ParserError.InvalidFormat;
        const id = id_line[1..];

        // Line 2: Sequence
        const seq_line = (try self.reader.readUntilDelimiterOrEof(out_buffer[id_line.len..], '\n')) orelse return ParserError.IncompleteRecord;
        const seq = seq_line;

        // Line 3: +ID (or just +)
        const plus_line = (try self.reader.readUntilDelimiterOrEof(out_buffer[id_line.len + seq_line.len ..], '\n')) orelse return ParserError.IncompleteRecord;
        if (plus_line.len == 0 or plus_line[0] != '+') return ParserError.InvalidFormat;

        // Line 4: Quality
        const qual_line = (try self.reader.readUntilDelimiterOrEof(out_buffer[id_line.len + seq_line.len + plus_line.len ..], '\n')) orelse return ParserError.IncompleteRecord;
        const qual = qual_line;

        const read = Read{
            .id = id,
            .seq = seq,
            .qual = qual,
        };

        if (!read.validate()) return ParserError.MismatchedSequenceQuality;

        return read;
    }
};

test "FastqParser test" {
    const allocator = std.testing.allocator;
    const content =
        \\@READ_1
        \\AGCT
        \\+
        \\IIII
        \\@READ_2
        \\GCTA
        \\+
        \\JJJJ
    ;
    var stream = std.io.fixedBufferStream(content);
    var parser = try FastqParser.init(allocator, stream.reader().any(), 1024);
    defer parser.deinit();

    var out_buffer: [1024]u8 = undefined;

    const read1 = (try parser.next(&out_buffer)).?;
    try std.testing.expectEqualStrings("READ_1", read1.id);
    try std.testing.expectEqualStrings("AGCT", read1.seq);
    try std.testing.expectEqualStrings("IIII", read1.qual);

    const read2 = (try parser.next(&out_buffer)).?;
    try std.testing.expectEqualStrings("READ_2", read2.id);
    try std.testing.expectEqualStrings("GCTA", read2.seq);
    try std.testing.expectEqualStrings("JJJJ", read2.qual);

    const read3 = try parser.next(&out_buffer);
    try std.testing.expect(read3 == null);
}
