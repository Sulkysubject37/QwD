const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    read_count: usize = 0,
    stages: std.ArrayListUnmanaged(stage_mod.Stage),

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return Scheduler{
            .allocator = allocator,
            .read_count = 0,
            .stages = .empty,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        self.stages.deinit(self.allocator);
    }

    /// Register a new processing stage.
    pub fn registerStage(self: *Scheduler, stage: stage_mod.Stage) !void {
        try self.stages.append(self.allocator, stage);
    }

    /// Receive a parsed read and forward it to registered processing stages.
    /// If a stage returns false, processing for this read stops.
    pub fn process(self: *Scheduler, read: parser.Read) !void {
        self.read_count += 1;
        var r = read; // Local copy allows stages to modify slices in-place
        for (self.stages.items) |stage| {
            const continue_processing = try stage.processRead(&r);
            if (!continue_processing) break;
        }
    }

    /// Finalize all registered stages.
    pub fn finalize(self: *Scheduler) !void {
        for (self.stages.items) |stage| {
            try stage.finalize();
        }
    }

    /// Report all registered stages.
    pub fn report(self: *Scheduler, writer: std.Io.Writer) void {
        for (self.stages.items) |stage| {
            stage.report(writer);
        }
    }
};

test "Scheduler test with dummy stage" {
    
    var scheduler = Scheduler.init(std.heap.c_allocator);
    defer scheduler.deinit();

    // Define a dummy stage
    const DummyStage = struct {
        processed: usize = 0,
        should_continue: bool = true,

        pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
            _ = read;
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.processed += 1;
            return self.should_continue;
        }

        pub fn finalize(ptr: *anyopaque) !void {
            _ = ptr;
        }

        pub fn report(ptr: *anyopaque, writer: std.Io.Writer) void {
            _ = ptr;
            _ = writer;
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

    var dummy1 = DummyStage{ .should_continue = false };
    var dummy2 = DummyStage{};
    try scheduler.registerStage(dummy1.stage());
    try scheduler.registerStage(dummy2.stage());

    const read = parser.Read{
        .id = "test",
        .seq = "ATGC",
        .qual = "IIII",
    };
    try scheduler.process(read);
    try std.testing.expectEqual(@as(usize, 1), scheduler.read_count);
    try std.testing.expectEqual(@as(usize, 1), dummy1.processed);
    try std.testing.expectEqual(@as(usize, 0), dummy2.processed); // Filtered out
}
