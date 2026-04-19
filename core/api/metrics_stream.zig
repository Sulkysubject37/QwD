const std = @import("std");
const structured_output = @import("../output/structured_output.zig");

pub const MetricsStream = struct {
    writer: std.Io.Writer,
    interval: usize = 1000,
    last_emit: usize = 0,

    pub fn init(writer: std.Io.Writer, interval: usize) MetricsStream {
        return .{
            .writer = writer,
            .interval = interval,
        };
    }

    pub fn update(self: *MetricsStream, current_reads: usize) !void {
        if (current_reads >= self.last_emit + self.interval) {
            try structured_output.writeNdjsonProcess(current_reads, self.writer);
            self.last_emit = current_reads;
        }
    }
};
