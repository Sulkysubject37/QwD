const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const simd = @import("simd_ops");

pub const GcStage = struct {
    gc_bases: usize = 0,
    total_bases: usize = 0,
    gc_ratio: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_bases += read.seq.len;
        
        if (simd.simd_enabled()) {
            self.gc_bases += simd.countGcSimd(read.seq);
        } else {
            for (read.seq) |base| {
                if (base == 'G' or base == 'C' or base == 'g' or base == 'c') {
                    self.gc_bases += 1;
                }
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

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("GC Report:\n", .{}) catch {};
        writer.print("  GC Content: {d:.2}%\n", .{self.gc_ratio * 100.0}) catch {};
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
