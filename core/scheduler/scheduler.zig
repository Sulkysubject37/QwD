const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const Scheduler = struct {
    read_count: usize = 0,
    stages: std.ArrayList(stage_mod.Stage),

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return Scheduler{
            .read_count = 0,
            .stages = std.ArrayList(stage_mod.Stage).init(allocator),
        };
    }

    pub fn deinit(self: *Scheduler) void {
        self.stages.deinit();
    }

    /// Register a new processing stage.
    pub fn registerStage(self: *Scheduler, stage: stage_mod.Stage) !void {
        try self.stages.append(stage);
    }

    /// Receive a parsed read and forward it to all registered processing stages.
    pub fn process(self: *Scheduler, read: parser.Read) !void {
        self.read_count += 1;
        for (self.stages.items) |stage| {
            try stage.process(read);
        }
    }

    /// Finalize all registered stages.
    pub fn finalize(self: *Scheduler) !void {
        for (self.stages.items) |stage| {
            try stage.finalize();
        }
    }

    /// Report all registered stages.
    pub fn report(self: *Scheduler) void {
        for (self.stages.items) |stage| {
            stage.report();
        }
    }
};

test "Scheduler test with dummy stage" {
    const allocator = std.testing.allocator;
    var scheduler = Scheduler.init(allocator);
    defer scheduler.deinit();

    // Define a dummy stage
    const DummyStage = struct {
        processed: usize = 0,

        pub fn process(ptr: *anyopaque, read: parser.Read) !void {
            _ = read;
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.processed += 1;
        }

        pub fn finalize(ptr: *anyopaque) !void {
            _ = ptr;
        }

        pub fn report(ptr: *anyopaque) void {
            _ = ptr;
        }

        pub fn stage(self: *@This()) stage_mod.Stage {
            return .{
                .ptr = self,
                .vtable = &.{
                    .process = process,
                    .finalize = finalize,
                    .report = report,
                },
            };
        }
    };

    var dummy = DummyStage{};
    try scheduler.registerStage(dummy.stage());

    const read = parser.Read{
        .id = "test",
        .seq = "ATGC",
        .qual = "IIII",
    };
    try scheduler.process(read);
    try std.testing.expectEqual(@as(usize, 1), scheduler.read_count);
    try std.testing.expectEqual(@as(usize, 1), dummy.processed);
}
