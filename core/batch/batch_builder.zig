const std = @import("std");
const parser_mod = @import("parser");
const read_batch_mod = @import("read_batch");

pub const BatchBuilder = struct {
    allocator: std.mem.Allocator,
    parser: *parser_mod.FastqParser,
    buffer: []u8, 

    pub fn init(allocator: std.mem.Allocator, parser: *parser_mod.FastqParser) !BatchBuilder {
        return BatchBuilder{
            .allocator = allocator,
            .parser = parser,
            .buffer = try allocator.alloc(u8, 65536), 
        };
    }

    pub fn deinit(self: *BatchBuilder) void {
        self.allocator.free(self.buffer);
    }

    pub fn fillBatch(self: *BatchBuilder, batch: *read_batch_mod.ReadBatch) !bool {
        batch.clear();
        
        while (batch.count < batch.capacity) {
            if (try self.parser.next(self.buffer)) |read| {
                _ = batch.add(read.seq, read.qual, read.id.len);
            } else {
                break; // EOF
            }
        }
        return batch.count > 0;
    }
};
