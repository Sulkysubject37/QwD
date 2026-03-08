const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const GcContentStage = struct {
    gc_bases: usize = 0,
    total_bases: usize = 0,
    gc_ratio: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (read.seq) |base| {
            self.total_bases += 1;
            if (base == 'G' or base == 'C' or base == 'g' or base == 'c') {
                self.gc_bases += 1;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_bases > 0) {
            self.gc_ratio = @as(f64, @floatFromInt(self.gc_bases)) / @as(f64, @floatFromInt(self.total_bases));
        }
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("Global GC Content Report:\n", .{});
        std.debug.print("  GC Content: {d:.2}%\n", .{self.gc_ratio * 100.0});
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
