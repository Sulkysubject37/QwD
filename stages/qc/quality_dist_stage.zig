const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

/// Phase Tax-ed: Quality Distribution Stage
/// Collects a 2D histogram of Quality Scores (0-40) per base position (0-1024).
/// Uses heap allocation to prevent stack overflow (Segfault fix).
pub const QualityDistStage = struct {
    // [position][score]
    dist: *[1024][41]u64,
    max_pos_seen: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*QualityDistStage {
        const self = try allocator.create(QualityDistStage);
        const data = try allocator.create([1024][41]u64);
        @memset(std.mem.asBytes(data), 0);
        
        self.* = .{
            .dist = data,
            .max_pos_seen = 0,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *QualityDistStage) void {
        self.allocator.destroy(self.dist);
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const len = read.qual.len;
        if (len > self.max_pos_seen) self.max_pos_seen = @min(len, 1024);

        for (read.qual, 0..) |q, i| {
            if (i >= 1024) break;
            const score = if (q >= 33) q - 33 else 0;
            const idx = @min(score, 40);
            self.dist[i][idx] += 1;
        }
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        _ = bp;
        
        const limit = @min(block.max_read_len, 1024);
        if (limit > self.max_pos_seen) self.max_pos_seen = limit;

        // Vectorized Quality Accumulation
        var pos: usize = 0;
        while (pos < limit) : (pos += 1) {
            const column = block.qualities[pos];
            var read_idx: usize = 0;
            
            // Process in chunks of 32 using SIMD hints
            while (read_idx + 32 <= block.read_count) : (read_idx += 32) {
                const vec: @Vector(32, u8) = column[read_idx..][0..32].*;
                inline for (0..32) |i| {
                    const q = vec[i];
                    if (q >= 33) {
                        const score = q - 33;
                        const idx = @min(score, 40);
                        self.dist[pos][idx] += 1;
                    }
                }
            }
            
            // Residuals
            while (read_idx < block.read_count) : (read_idx += 1) {
                const q = column[read_idx];
                if (q >= 33) {
                    const score = q - 33;
                    const idx = @min(score, 40);
                    self.dist[pos][idx] += 1;
                }
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void { _ = ptr; }

    pub fn merge(ptr: *anyopaque, other_ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        if (other.max_pos_seen > self.max_pos_seen) self.max_pos_seen = other.max_pos_seen;
        for (0..1024) |i| {
            for (0..41) |j| {
                self.dist[i][j] += other.dist[i][j];
            }
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Quality Distribution Stage: Analyzed up to {d} bp.\n", .{self.max_pos_seen}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.writeAll("\"quality_dist\": { \"max_pos\": ");
        try writer.print("{d}, \"data\": [", .{self.max_pos_seen});
        
        const limit = if (self.max_pos_seen == 0) 0 else self.max_pos_seen;
        for (0..limit) |pos| {
            if (pos > 0) try writer.writeAll(",");
            try writer.writeAll("[");
            for (0..41) |score| {
                if (score > 0) try writer.writeAll(",");
                try writer.print("{d}", .{self.dist[pos][score]});
            }
            try writer.writeAll("]");
        }
        try writer.writeAll("]}");
    }

    pub fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const new_self = try allocator.create(@This());
        const data = try allocator.create([1024][41]u64);
        @memcpy(std.mem.asBytes(data), std.mem.asBytes(self.dist));
        
        new_self.* = .{
            .dist = data,
            .max_pos_seen = self.max_pos_seen,
            .allocator = allocator,
        };
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

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &VTABLE,
        };
    }
};
