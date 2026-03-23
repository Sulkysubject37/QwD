const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const NStatisticsStage = struct {
    total_bases: u64 = 0,
    length_histogram: [30000]u32 = [_]u32{0} ** 30000,
    n10: usize = 0,
    n25: usize = 0,
    n50: usize = 0,
    n75: usize = 0,
    n90: usize = 0,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        self.total_bases += len;
        
        const idx = if (len >= 30000) 29999 else len;
        self.length_histogram[idx] += 1;

        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bitplanes: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) anyerror!bool {
        _ = bitplanes;
        return processBlock(ptr, block);
    }

    pub fn processBlock(ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (0..block.read_count) |i| {
            const len = block.read_lengths[i];
            self.total_bases += len;
            const idx = if (len >= 30000) 29999 else len;
            self.length_histogram[idx] += 1;
        }
        return true;
    }

    pub fn processRawBatch(ptr: *anyopaque, reads: []const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        for (reads) |read| {
            const len = read.seq.len;
            self.total_bases += len;
            const idx = if (len >= 30000) 29999 else len;
            self.length_histogram[idx] += 1;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_bases == 0) return;

        const t10 = self.total_bases / 10;
        const t25 = self.total_bases / 4;
        const t50 = self.total_bases / 2;
        const t75 = (self.total_bases * 3) / 4;
        const t90 = (self.total_bases * 9) / 10;
        
        var cumulative_bases: u64 = 0;
        
        var i: usize = 29999;
        while (i > 0) : (i -= 1) {
            cumulative_bases += @as(u64, self.length_histogram[i]) * i;
            if (self.n10 == 0 and cumulative_bases >= t10) self.n10 = i;
            if (self.n25 == 0 and cumulative_bases >= t25) self.n25 = i;
            if (self.n50 == 0 and cumulative_bases >= t50) self.n50 = i;
            if (self.n75 == 0 and cumulative_bases >= t75) self.n75 = i;
            if (self.n90 == 0 and cumulative_bases >= t90) self.n90 = i;
            
            if (self.n90 != 0) break;
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_bases += other.total_bases;
        for (0..30000) |i| {
            self.length_histogram[i] += other.length_histogram[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("N-Statistics Report:\n", .{}) catch {};
        writer.print("  N10: {d}\n", .{self.n10}) catch {};
        writer.print("  N25: {d}\n", .{self.n25}) catch {};
        writer.print("  N50: {d}\n", .{self.n50}) catch {};
        writer.print("  N75: {d}\n", .{self.n75}) catch {};
        writer.print("  N90: {d}\n", .{self.n90}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print(
            \\"n_statistics": {{
            \\  "n10": {d},
            \\  "n25": {d},
            \\  "n50": {d},
            \\  "n75": {d},
            \\  "n90": {d}
            \\}}
        , .{ self.n10, self.n25, self.n50, self.n75, self.n90 });
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .processRawBatch = processRawBatch,
                .processBlock = processBlock,
                .processBitplanes = processBitplanes,
                .finalize = finalize,
                .report = report,
                .reportJson = reportJson,
                .merge = merge,
            },
        };
    }
};
