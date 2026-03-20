const std = @import("std");
const parser_mod = @import("parser");
const raw_batch = @import("raw_batch");

pub const RawBatchBuilder = struct {
    parser: *parser_mod.FastqParser,

    pub fn init(parser: *parser_mod.FastqParser) RawBatchBuilder {
        return RawBatchBuilder{ .parser = parser };
    }

    pub fn fillBatch(self: *RawBatchBuilder, batch: *raw_batch.RawBatch) !bool {
        batch.clear();
        var dummy: [1]u8 = undefined;

        while (batch.count < batch.capacity) {
            if (try self.parser.next(&dummy)) |read| {
                _ = batch.add(read.seq, read.qual);
            } else {
                break;
            }
        }
        return batch.count > 0;
    }
};
