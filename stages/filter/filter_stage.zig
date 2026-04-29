const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const FilterStage = struct {
    min_quality: f64,
    reads_seen: usize = 0,
    reads_passed: usize = 0,
    reads_filtered: usize = 0,

    pub fn init(min_quality: f64) FilterStage {
        return .{
            .min_quality = min_quality,
        };
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.reads_seen += 1;

        if (read.qual.len == 0) {
            self.reads_passed += 1;
            return true;
        }

        var sum: u64 = 0;
        for (read.qual) |q| {
            const phred = if (q >= 33) q - 33 else 0;
            sum += phred;
        }

        const avg = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(read.qual.len));

        if (avg >= self.min_quality) {
            self.reads_passed += 1;
            return true;
        } else {
            self.reads_filtered += 1;
            return false;
        }
    }

    pub fn processBitplanes(_: *anyopaque, _: *const @import("bitplanes").BitplaneCore, _: *const @import("fastq_block").FastqColumnBlock) anyerror!bool {
        // Fallback to scalar processing for Filter
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}

    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Filter (min_qual={d:.2}): {d}/{d} passed\n", .{ self.min_quality, self.reads_passed, self.reads_seen }) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"filter\": {{\"reads_seen\": {d}, \"reads_passed\": {d}, \"reads_filtered\": {d}}}", .{
            self.reads_seen,
            self.reads_passed,
            self.reads_filtered,
        });
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.reads_seen += other.reads_seen;
        self.reads_passed += other.reads_passed;
        self.reads_filtered += other.reads_filtered;
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(FilterStage);
        new_self.* = FilterStage.init(self.min_quality);
        return new_self;
    }

    pub fn stage(self: *FilterStage) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &VTABLE,
        };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = FilterStage.process,
    .finalize = FilterStage.finalize,
    .report = FilterStage.report,
    .reportJson = FilterStage.reportJson,
    .merge = FilterStage.merge,
    .clone = FilterStage.clone,
};
