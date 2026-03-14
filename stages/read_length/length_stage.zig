const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const LengthStage = struct {
    total_reads: usize = 0,
    total_length: u64 = 0,
    min_length: usize = std.math.maxInt(usize),
    max_length: usize = 0,
    mean_length: f64 = 0.0,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        self.total_reads += 1;
        self.total_length += len;
        if (len < self.min_length) self.min_length = len;
        if (len > self.max_length) self.max_length = len;
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_reads > 0) {
            self.mean_length = @as(f64, @floatFromInt(self.total_length)) / @as(f64, @floatFromInt(self.total_reads));
        } else {
            self.min_length = 0;
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.total_length += other.total_length;
        if (other.min_length < self.min_length) self.min_length = other.min_length;
        if (other.max_length > self.max_length) self.max_length = other.max_length;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Read Length Report:\n", .{}) catch {};
        writer.print("  Mean length: {d:.2}\n", .{self.mean_length}) catch {};
        writer.print("  Min length: {d}\n", .{self.min_length}) catch {};
        writer.print("  Max length: {d}\n", .{self.max_length}) catch {};
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
