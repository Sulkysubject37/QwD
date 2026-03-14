const std = @import("std");
const parser_mod = @import("parser");
const read_batch_mod = @import("read_batch");

pub const BatchBuilder = struct {
    allocator: std.mem.Allocator,
    parser: *parser_mod.FastqParser,

    pub fn init(allocator: std.mem.Allocator, parser: *parser_mod.FastqParser) !BatchBuilder {
        return BatchBuilder{
            .allocator = allocator,
            .parser = parser,
        };
    }

    pub fn deinit(self: *BatchBuilder) void {
        _ = self;
    }

    pub fn fillBatch(self: *BatchBuilder, batch: *read_batch_mod.ReadBatch) !bool {
        batch.clear();
        
        // Use a dummy buffer for parser.next signature compliance if not mmap
        var dummy: [1]u8 = undefined;

        while (batch.count < batch.capacity) {
            if (try self.parser.next(&dummy)) |read| {
                _ = batch.add(read.seq, read.qual, read.id.len);
            } else {
                break; // EOF
            }
        }
        return batch.count > 0;
    }
};
