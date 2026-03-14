const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const BasicStatsStage = struct {
    total_reads: usize = 0,
    total_bases: usize = 0,
    min_read_length: usize = std.math.maxInt(usize),
    max_read_length: usize = 0,
    mean_read_length: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        
        self.total_reads += 1;
        self.total_bases += len;
        if (len < self.min_read_length) self.min_read_length = len;
        if (len > self.max_read_length) self.max_read_length = len;
        
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_reads > 0) {
            self.mean_read_length = @as(f64, @floatFromInt(self.total_bases)) / @as(f64, @floatFromInt(self.total_reads));
        } else {
            self.min_read_length = 0;
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        
        self.total_reads += other.total_reads;
        self.total_bases += other.total_bases;
        if (other.min_read_length < self.min_read_length) self.min_read_length = other.min_read_length;
        if (other.max_read_length > self.max_read_length) self.max_read_length = other.max_read_length;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Basic Statistics:\n", .{}) catch {};
        writer.print("  Total reads: {d}\n", .{self.total_reads}) catch {};
        writer.print("  Total bases: {d}\n", .{self.total_bases}) catch {};
        writer.print("  Min length:  {d}\n", .{self.min_read_length}) catch {};
        writer.print("  Max length:  {d}\n", .{self.max_read_length}) catch {};
        writer.print("  Mean length: {d:.2}\n", .{self.mean_read_length}) catch {};
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
