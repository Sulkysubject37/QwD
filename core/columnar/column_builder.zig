const std = @import("std");
const parser_mod = @import("parser");
const fastq_block = @import("fastq_block");

pub const ColumnBuilder = struct {
    allocator: std.mem.Allocator,
    parser: *parser_mod.FastqParser,

    pub fn init(allocator: std.mem.Allocator, parser: *parser_mod.FastqParser) ColumnBuilder {
        return ColumnBuilder{
            .allocator = allocator,
            .parser = parser,
        };
    }

    pub fn fillBlock(self: *ColumnBuilder, block: *fastq_block.FastqColumnBlock) !bool {
        block.clear();
        
        // Use a dummy buffer for parser.next
        var dummy: [1]u8 = undefined;

        while (block.read_count < block.capacity) {
            if (try self.parser.next(&dummy)) |read| {
                _ = block.addRead(read.seq, read.qual);
            } else {
                break;
            }
        }
        return block.read_count > 0;
    }
};
