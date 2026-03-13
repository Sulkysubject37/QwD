const std = @import("std");

pub const ParserError = error{
    InvalidFormat,
    IncompleteRecord,
    MismatchedSequenceQuality,
    StreamError,
    MalformedCigar,
};

pub fn logError(msg: []const u8) void {
    std.debug.print("Parser Error: {s}
", .{msg});
}
