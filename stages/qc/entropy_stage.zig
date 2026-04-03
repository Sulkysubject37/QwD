const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const entropy_lut_mod = @import("entropy_lut");

pub const EntropyStage = struct {
    total_reads: usize = 0,
    total_entropy_sum: f64 = 0.0,
    low_complexity_reads: usize = 0,
    mean_entropy: f64 = 0.0,
    
    pub fn init(allocator: std.mem.Allocator) !*EntropyStage {
        const self = try allocator.create(EntropyStage);
        self.* = .{};
        return self;
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.seq.len;
        if (len == 0) return true;

        var base_counts = [_]usize{0} ** 4;
        for (read.seq) |base| {
            switch (base) {
                'A', 'a' => base_counts[0] += 1,
                'C', 'c' => base_counts[1] += 1,
                'G', 'g' => base_counts[2] += 1,
                'T', 't' => base_counts[3] += 1,
                else => {},
            }
        }

        const entropy = entropy_lut_mod.global_lut.getEntropy(base_counts, len);
        self.total_reads += 1;
        self.total_entropy_sum += entropy;
        if (entropy < 1.5) self.low_complexity_reads += 1;

        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        _ = bp;
        
        for (0..block.read_count) |read_idx| {
            const len = block.read_lengths[read_idx];
            if (len == 0) continue;

            var base_counts = [_]usize{0} ** 4;
            for (0..len) |pos| {
                const base = block.bases[pos][read_idx];
                switch (base) {
                    'A', 'a' => base_counts[0] += 1,
                    'C', 'c' => base_counts[1] += 1,
                    'G', 'g' => base_counts[2] += 1,
                    'T', 't' => base_counts[3] += 1,
                    else => {},
                }
            }

            const entropy = entropy_lut_mod.global_lut.getEntropy(base_counts, len);
            self.total_reads += 1;
            self.total_entropy_sum += entropy;
            if (entropy < 1.5) self.low_complexity_reads += 1;
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.total_reads > 0) {
            self.mean_entropy = self.total_entropy_sum / @as(f64, @floatFromInt(self.total_reads));
        }
    }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.total_entropy_sum += other.total_entropy_sum;
        self.low_complexity_reads += other.low_complexity_reads;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("\n[Entropy Analysis]\n", .{}) catch {};
        writer.print("  Mean Entropy: {d:.4} bits/base\n", .{self.mean_entropy}) catch {};
        writer.print("  Low Complexity Reads: {d} ({d:.2}%)\n", .{
            self.low_complexity_reads,
            if (self.total_reads > 0) @as(f64, @floatFromInt(self.low_complexity_reads)) * 100.0 / @as(f64, @floatFromInt(self.total_reads)) else 0.0
        }) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"entropy\": {{\"mean_entropy\": {d:.4}, \"low_complexity_reads\": {d}}}", .{ self.mean_entropy, self.low_complexity_reads });
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(@This());
        new_self.* = self.*;
        return new_self;
    }

    const VTABLE = stage_mod.Stage.VTable{
        .process = process,
        .processBitplanes = processBitplanes,
        .finalize = finalize,
        .report = report,
        .reportJson = reportJson,
        .merge = merge,
        .clone = clone,
    };

    pub fn stage(self: *const @This()) stage_mod.Stage {
        return .{
            .ptr = @constCast(self),
            .vtable = &VTABLE,
        };
    }
};
