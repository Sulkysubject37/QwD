const std = @import("std");
const block_reader = @import("../io/block_reader.zig");

pub const Read = struct {
    header: []const u8,
    sequence: []const u8,
    qualities: []const u8,
    
    pub fn isValid(self: *const Read) bool {
        return self.sequence.len == self.qualities.len and self.sequence.len > 0;
    }
};

pub const FastqParser = struct {
    br: block_reader.BlockReader,
    allocator: std.mem.Allocator,
    
    // State machine for parsing
    state: enum { Header, Sequence, Plus, Quality } = .Header,
    current_read: Read = undefined,
    
    // Buffers for current entry to handle items that span blocks
    header_buf: std.ArrayListUnmanaged(u8) = .{},
    seq_buf: std.ArrayListUnmanaged(u8) = .{},
    qual_buf: std.ArrayListUnmanaged(u8) = .{},

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader, buffer_size: usize) !FastqParser {
        return FastqParser{
            .br = try block_reader.BlockReader.init(allocator, reader, buffer_size),
            .allocator = allocator,
        };
    }

    pub fn initMmap(allocator: std.mem.Allocator, file: std.fs.File) !FastqParser {
        return FastqParser{
            .br = try block_reader.BlockReader.initMmap(allocator, file),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FastqParser) void {
        self.br.deinit(self.allocator);
        self.header_buf.deinit(self.allocator);
        self.seq_buf.deinit(self.allocator);
        self.qual_buf.deinit(self.allocator);
    }

    pub fn next(self: *FastqParser, scratch: []u8) !?Read {
        var scratch_pos: usize = 0;
        
        while (true) {
            if (self.br.pos >= self.br.end) {
                const read_len = try self.br.fill();
                if (read_len == 0) {
                    if (self.br.pos >= self.br.end) return null; // EOF
                }
            }

            const chunk = self.br.buffer[self.br.pos..self.br.end];
            if (chunk.len == 0) return null;

            var i: usize = 0;
            switch (self.state) {
                .Header => {
                    if (chunk[i] != '@') {
                        // Skip until we find a header
                        while (i < chunk.len and chunk[i] != '@') i += 1;
                        if (i == chunk.len) {
                            self.br.pos += i;
                            continue;
                        }
                    }
                    
                    const start = i;
                    while (i < chunk.len and chunk[i] != '\n') i += 1;
                    
                    if (i < chunk.len) { // Found newline
                        const len = i - start;
                        if (scratch_pos + len > scratch.len) return error.BufferTooSmall;
                        std.mem.copyForwards(u8, scratch[scratch_pos..], chunk[start..i]);
                        // Trim trailing \r if present (Windows line endings)
                        var actual_len = len;
                        if (actual_len > 0 and scratch[scratch_pos + actual_len - 1] == '\r') {
                            actual_len -= 1;
                        }
                        self.current_read.header = scratch[scratch_pos..scratch_pos + actual_len];
                        scratch_pos += actual_len;
                        self.state = .Sequence;
                        i += 1; // Skip newline
                    } else { // Need more data
                        return error.NotImplemented; // Spans block - simplifying for now
                    }
                    self.br.pos += i;
                },
                .Sequence => {
                    const start = i;
                    while (i < chunk.len and chunk[i] != '\n') i += 1;
                    
                    if (i < chunk.len) {
                        const len = i - start;
                        if (scratch_pos + len > scratch.len) return error.BufferTooSmall;
                        std.mem.copyForwards(u8, scratch[scratch_pos..], chunk[start..i]);
                        var actual_len = len;
                        if (actual_len > 0 and scratch[scratch_pos + actual_len - 1] == '\r') {
                            actual_len -= 1;
                        }
                        self.current_read.sequence = scratch[scratch_pos..scratch_pos + actual_len];
                        scratch_pos += actual_len;
                        self.state = .Plus;
                        i += 1;
                    }
                    self.br.pos += i;
                },
                .Plus => {
                    while (i < chunk.len and chunk[i] != '\n') i += 1;
                    if (i < chunk.len) {
                        self.state = .Quality;
                        i += 1;
                    }
                    self.br.pos += i;
                },
                .Quality => {
                    const start = i;
                    while (i < chunk.len and chunk[i] != '\n') i += 1;
                    
                    if (i < chunk.len) {
                        const len = i - start;
                        if (scratch_pos + len > scratch.len) return error.BufferTooSmall;
                        std.mem.copyForwards(u8, scratch[scratch_pos..], chunk[start..i]);
                        var actual_len = len;
                        if (actual_len > 0 and scratch[scratch_pos + actual_len - 1] == '\r') {
                            actual_len -= 1;
                        }
                        self.current_read.qualities = scratch[scratch_pos..scratch_pos + actual_len];
                        self.state = .Header;
                        i += 1;
                        self.br.pos += i;
                        
                        if (!self.current_read.isValid()) return error.InvalidFastq;
                        return self.current_read;
                    }
                    self.br.pos += i;
                }
            }
        }
    }
};
