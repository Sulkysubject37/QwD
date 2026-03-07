const std = @import("std");
const parser = @import("parser");

pub const Scheduler = struct {
    read_count: usize = 0,

    /// Receive a parsed read and forward it to processing stages.
    pub fn process(self: *Scheduler, read: parser.Read) !void {
        _ = read; // Placeholder for future stage processing.
        self.read_count += 1;
    }
};

test "Scheduler test" {
    var scheduler = Scheduler{};
    const read = parser.Read{
        .id = "test",
        .seq = "ATGC",
        .qual = "IIII",
    };
    try scheduler.process(read);
    try std.testing.expectEqual(@as(usize, 1), scheduler.read_count);
    try scheduler.process(read);
    try std.testing.expectEqual(@as(usize, 2), scheduler.read_count);
}
