const std = @import("std");
const parser_mod = @import("parser");
const read_batch_mod = @import("read_batch");

pub const BatchBuilder = struct {
    allocator: std.mem.Allocator,
    parser: *parser_mod.FastqParser,
    batch: read_batch_mod.ReadBatch,
    buffer: []u8, // Used to satisfy the parser signature if needed

    pub fn init(allocator: std.mem.Allocator, parser: *parser_mod.FastqParser, batch_capacity: usize) !BatchBuilder {
        return BatchBuilder{
            .allocator = allocator,
            .parser = parser,
            .batch = try read_batch_mod.ReadBatch.init(allocator, batch_capacity),
            .buffer = try allocator.alloc(u8, 65536), // Dummy buffer since FastqParser currently takes one
        };
    }

    pub fn deinit(self: *BatchBuilder) void {
        self.batch.deinit(self.allocator);
        self.allocator.free(self.buffer);
    }

    pub fn nextBatch(self: *BatchBuilder) !?*read_batch_mod.ReadBatch {
        self.batch.clear();
        
        while (self.batch.count < self.batch.capacity) {
            if (try self.parser.next(self.buffer)) |read| {
                _ = self.batch.add(read.seq, read.qual, read.id.len);
            } else {
                break; // EOF
            }
        }
        if (self.batch.count > 0) {
            return &self.batch;
        }
        return null;
    }
};
