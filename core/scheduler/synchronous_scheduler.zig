const std = @import("std");
const stage_mod = @import("stage");
const parser_mod = @import("parser");
const reader_interface = @import("reader_interface");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");

pub const SynchronousScheduler = struct {
    allocator: std.mem.Allocator,
    stages: [32]stage_mod.Stage = undefined,
    stage_count: usize = 0,
    // Generic hook to break dependency on telemetry_interface.zig
    telemetry_hook: ?*const anyopaque = null,

    pub fn init(allocator: std.mem.Allocator) SynchronousScheduler {
        return .{
            .allocator = allocator,
            .stage_count = 0,
        };
    }

    pub fn addStage(self: *SynchronousScheduler, stage: stage_mod.Stage) !void {
        if (self.stage_count < 32) {
            self.stages[self.stage_count] = stage;
            self.stage_count += 1;
        }
    }

    pub fn run(self: *SynchronousScheduler, reader: reader_interface.Reader) !void {
        var parser = try parser_mod.FastqParser.init(self.allocator, reader, 1024 * 1024);
        defer parser.deinit();

        var column_block = try fastq_block.FastqColumnBlock.init(self.allocator, 1024, 1024);
        defer column_block.deinit(self.allocator);

        var bp_core = try bitplanes.BitplaneCore.init(self.allocator, 1024, 1024);
        defer bp_core.deinit();

        while (true) {
            column_block.clear();
            var i: usize = 0;
            var max_len: usize = 0;
            while (i < 1024) : (i += 1) {
                const read = parser.next() catch |err| {
                    if (err == error.EndOfStream) break else return err;
                };
                const len = read.seq.len;
                if (len > max_len) max_len = len;
                _ = column_block.add(read.seq, read.qual) catch break;
            }
            if (i == 0) break;
            
            column_block.read_count = i;
            column_block.active_max_len = max_len;
            
            bp_core.fromColumnBlock(&column_block);

            if (self.telemetry_hook) |hook_ptr| {
                const HookFn = *const fn (
                    *const fastq_block.FastqColumnBlock, 
                    *const bitplanes.BitplaneCore,
                    [*:0]const u8,
                    usize,
                ) callconv(.c) void;
                const hook: HookFn = @ptrCast(@alignCast(hook_ptr));
                hook(&column_block, &bp_core, "Analysis", 0);
            }

            for (0..self.stage_count) |stage_idx| {
                _ = try self.stages[stage_idx].processBitplanes(&bp_core, &column_block);
            }
        }
    }

    pub fn scheduler(self: *SynchronousScheduler) @import("scheduler_interface").Scheduler {
        return @import("scheduler_interface").Scheduler.init(self, &.{
            .addStage = struct {
                fn addStage(ctx: *anyopaque, stage: stage_mod.Stage) anyerror!void {
                    const s: *SynchronousScheduler = @ptrCast(@alignCast(ctx));
                    return s.addStage(stage);
                }
            }.addStage,
            .run = struct {
                fn run(ctx: *anyopaque, reader: reader_interface.Reader) anyerror!void {
                    const s: *SynchronousScheduler = @ptrCast(@alignCast(ctx));
                    return s.run(reader);
                }
            }.run,
        });
    }
};
