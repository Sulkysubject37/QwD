const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const GcdistributionStage = struct {
    bins: [101]usize = [_]usize{0} ** 101,

    pub fn process(ptr: *anyopaque, read: *const parser.Read) anyerror!bool { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (read.seq.len == 0) return true;
        var gc: usize = 0;
        for (read.seq) |b| {
            switch (b) {
                'G', 'g', 'C', 'c' => gc += 1,
                else => {},
            }
        }
        const gc_perc = (gc * 100) / read.seq.len;
        self.bins[@min(gc_perc, 100)] += 1;
        return true; 
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        const active_len = block.active_max_len;

        var gc_totals = [_]u16{0} ** 1024;
        
        // BITPLANE ACCELERATION: Process 64 reads in parallel
        for (0..active_len) |col| {
            const offset = col * bp.u64_per_col;
            
            var i: usize = 0;
            while (i < bp.u64_per_col) : (i += 1) {
                var mask = bp.plane_g[offset + i] | bp.plane_c[offset + i];
                
                // TRUTH MASK: Mathematically ignore "ghost" data
                const reads_in_lane = if ((i + 1) * 64 <= read_count) @as(usize, 64) else if (i * 64 >= read_count) @as(usize, 0) else read_count % 64;
                if (reads_in_lane == 0) continue;
                
                const valid_mask = if (reads_in_lane == 64) ~@as(u64, 0) else (@as(u64, 1) << @as(u6, @intCast(reads_in_lane))) - 1;
                mask &= valid_mask;

                while (mask != 0) {
                    const bit = @ctz(mask);
                    gc_totals[i * 64 + bit] += 1;
                    mask &= mask - 1;
                }
            }
        }

        for (0..read_count) |i| {
            const len = block.read_lengths[i];
            if (len > 0) {
                const perc = (@as(usize, gc_totals[i]) * 100) / len;
                self.bins[@min(perc, 100)] += 1;
            }
        }
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn report(_: *anyopaque, _: *std.Io.Writer) void {}
    
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"gc_distribution\": {\"bins\": [");
        for (self.bins, 0..) |count, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.print("{d}", .{count});
        }
        try writer.writeAll("]}");
    }
    
    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..101) |i| {
            self.bins[i] += other.bins[i];
        }
    }
    
    pub fn clone(_: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const new_self = try allocator.create(GcdistributionStage);
        new_self.* = .{};
        return new_self;
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{ .ptr = self, .vtable = &VTABLE };
    }
};

const VTABLE = stage_mod.Stage.VTable{
    .process = GcdistributionStage.process,
    .finalize = GcdistributionStage.finalize,
    .report = GcdistributionStage.report,
    .reportJson = GcdistributionStage.reportJson,
    .merge = GcdistributionStage.merge,
    .clone = GcdistributionStage.clone,
    .processBitplanes = GcdistributionStage.processBitplanes,
};
