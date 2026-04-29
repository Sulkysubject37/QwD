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
            const continue_processing = try stage.process(&r);
            if (!continue_processing) break;
        }
    }

    /// Finalize all registered stages.
    pub fn finalize(self: *Scheduler) !void {
        for (self.stages.items) |stage| {
            try stage.finalize();
        }
    }

    /// Generate a summary report from all stages.
    pub fn report(self: *Scheduler, writer: anytype) void {
        for (self.stages.items) |stage| {
            stage.reportJson(writer) catch {};
        }
    }
    
    pub fn run(self: *Scheduler, reader: @import("reader_interface.zig").Reader, pipeline_ptr: anytype) !void {
        var fastq_parser = try @import("parser").FastqParser.init(self.allocator, reader, 256 * 1024);
        defer fastq_parser.deinit();
        
        var next_buf: [4096]u8 = undefined;
        while (try fastq_parser.next(&next_buf)) |read| {
            try self.process(read);
            pipeline_ptr.read_count += 1;
        }
        try self.finalize();
    }
};
