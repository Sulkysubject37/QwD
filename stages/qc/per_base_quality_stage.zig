const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const PerBaseQualityStage = struct {
    total_reads: usize = 0,
    mean_quality: [MAX_POS]f64 = [_]f64{0} ** MAX_POS,
    base_count: [MAX_POS]usize = [_]usize{0} ** MAX_POS,

    const MAX_POS = 1024;

    pub fn init(allocator: std.mem.Allocator) !*PerBaseQualityStage {
        const self = try allocator.create(PerBaseQualityStage);
        self.* = .{};
        return self;
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.total_reads += 1;
        const len = @min(read.seq.len, MAX_POS);
        for (0..len) |pos| {
            const q = @as(f64, @floatFromInt(read.qual[pos] - 33));
            self.mean_quality[pos] = (self.mean_quality[pos] * @as(f64, @floatFromInt(self.base_count[pos])) + q) / @as(f64, @floatFromInt(self.base_count[pos] + 1));
            self.base_count[pos] += 1;
        }
        return true;
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (0..block.read_count) |read_idx| {
            self.total_reads += 1;
            const len = @min(block.read_lengths[read_idx], MAX_POS);
            for (0..len) |pos| {
                const q = @as(f64, @floatFromInt(block.qualities[pos][read_idx]));
                self.mean_quality[pos] = (self.mean_quality[pos] * @as(f64, @floatFromInt(self.base_count[pos])) + q) / @as(f64, @floatFromInt(self.base_count[pos] + 1));
                self.base_count[pos] += 1;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        for (0..MAX_POS) |pos| {
            const total_bases = self.base_count[pos] + other.base_count[pos];
            if (total_bases > 0) {
                self.mean_quality[pos] = (self.mean_quality[pos] * @as(f64, @floatFromInt(self.base_count[pos])) + other.mean_quality[pos] * @as(f64, @floatFromInt(other.base_count[pos]))) / @as(f64, @floatFromInt(total_bases));
                self.base_count[pos] = total_bases;
            }
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Per-base Quality Report:\n", .{}) catch {};
        for (0..@min(10, MAX_POS)) |pos| {
            if (self.base_count[pos] == 0) break;
            writer.print("  Pos {d}: {d:.2}\n", .{ pos + 1, self.mean_quality[pos] }) catch {};
        }
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"per_base_quality\": {\"mean_qualities\": [");
        var first = true;
        for (0..MAX_POS) |pos| {
            if (self.base_count[pos] == 0) break;
            if (!first) try writer.writeAll(", ");
            try writer.print("{d:.2}", .{self.mean_quality[pos]});
            first = false;
        }
        try writer.writeAll("]}");
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        _ = bp;
        return processBlock(ptr, block);
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(@This());
        new_self.* = self.*;
        return new_self;
    }

    pub fn stage(self: *const @This()) stage_mod.Stage {
        return .{
            .ptr = @constCast(self),
            .vtable = &.{
                .process = process,
                .processBitplanes = processBitplanes,
                .finalize = finalize,
                .report = report,
                .reportJson = reportJson,
                .merge = merge,
                .clone = clone,
            },
        };
    }
};
