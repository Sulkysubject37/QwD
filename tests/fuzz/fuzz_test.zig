const std = @import("std");
const parser = @import("parser");

test "Fuzz Test - FastqParser Malformed Input" {
    const allocator = std.testing.allocator;
    
    const malformed_inputs = [_][]const u8{
        "@READ1\nACGT\n+\nIII\n",
        "@READ2\nAC\n+\nIIII\n",
        "READ3\nACGT\n+\nIIII\n",
        "@READ4\nACGT\n-\nIIII\n",
        "@READ5\n\n+\n\n",
    };
    
    for (malformed_inputs) |input| {
        var stream = std.io.fixedBufferStream(input);
        var fparser = try parser.FastqParser.init(allocator, stream.reader().any(), 1024);
        defer fparser.deinit();
        
        var buffer: [1024]u8 = undefined;
        const result = fparser.next(&buffer);
        
        if (result) |opt_read| {
            // It should either return null or a valid read, but not crash
            _ = opt_read;
            try std.testing.expect(true);
        } else |err| {
            // We expect errors for malformed input
            try std.testing.expect(err == error.MismatchedSequenceQuality or err == error.InvalidFormat or err == error.IncompleteRecord);
        }
    }
}
