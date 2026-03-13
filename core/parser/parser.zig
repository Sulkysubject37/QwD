const std = @import("std");
const block_reader = @import("block_reader");
const newline_scan = @import("newline_scan");

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
    BufferTooSmall,
};

pub const FastqParser = struct {
    br: block_reader.BlockReader,
    allocator: std.mem.Allocator,
    eof: bool = false,

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize) !FastqParser {
        return FastqParser{
            .br = try block_reader.BlockReader.init(allocator, reader, buffer_size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqParser) void {
        self.br.deinit(self.allocator);
    }

    fn readLine(self: *FastqParser, out_buffer: []u8) !?[]u8 {
        _ = out_buffer; // We are reading directly from the block buffer now
        
        while (true) {
            // Search for newline in remaining buffer
            if (newline_scan.indexOfNewline(self.br.buffer[self.br.pos..self.br.end])) |nl_idx| {
                const line = self.br.buffer[self.br.pos .. self.br.pos + nl_idx];
                self.br.pos += nl_idx + 1; // skip newline
                
                var trimmed = line;
                if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
                    trimmed = trimmed[0 .. trimmed.len - 1];
                }
                return trimmed;
            }
            
            if (self.eof) {
                // If EOF and some data remains, return it as the last line
                if (self.br.pos < self.br.end) {
                    const line = self.br.buffer[self.br.pos..self.br.end];
                    self.br.pos = self.br.end;
                    return line;
                }
                return null;
            }
            
            // If buffer is completely full and no newline, then it's too small
            if (self.br.pos == 0 and self.br.end == self.br.buffer.len) {
                return error.BufferTooSmall;
            }
            
            // Fill buffer and search again
            const read_len = try self.br.fill();
            if (read_len == 0) {
                self.eof = true;
            }
        }
    }

    /// Parses the next FASTQ record from the stream.
    pub fn next(self: *FastqParser, out_buffer: []u8) !?Read {
        // Line 1: @ID
        const id_line = (try self.readLine(out_buffer)) orelse return null;
        if (id_line.len == 0 or id_line[0] != '@') return ParserError.InvalidFormat;
        const id = id_line[1..];

        // Line 2: Sequence
        const seq = (try self.readLine(out_buffer)) orelse return ParserError.IncompleteRecord;

        // Line 3: +ID
        const plus_line = (try self.readLine(out_buffer)) orelse return ParserError.IncompleteRecord;
        if (plus_line.len == 0 or plus_line[0] != '+') return ParserError.InvalidFormat;

        // Line 4: Quality
        const qual = (try self.readLine(out_buffer)) orelse return ParserError.IncompleteRecord;

        const read = Read{
            .id = id,
            .seq = seq,
            .qual = qual,
        };

        if (!read.validate()) return ParserError.MismatchedSequenceQuality;

        return read;
    }
};
