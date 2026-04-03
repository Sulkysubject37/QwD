const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const NucleotideCompositionStage = struct {
    const MAX_POS = 10000;
    // Global counters for all positions combined
    a: usize = 0,
    c: usize = 0,
    g: usize = 0,
    t: usize = 0,
    n: usize = 0,
    total_bases: usize = 0,

    // Position-specific counters
    pos_a: [MAX_POS]usize = [_]usize{0} ** MAX_POS,
    pos_c: [MAX_POS]usize = [_]usize{0} ** MAX_POS,
    pos_g: [MAX_POS]usize = [_]usize{0} ** MAX_POS,
    pos_t: [MAX_POS]usize = [_]usize{0} ** MAX_POS,
    pos_n: [MAX_POS]usize = [_]usize{0} ** MAX_POS,
    max_len_seen: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !*NucleotideCompositionStage {
        const self = try allocator.create(NucleotideCompositionStage);
        self.* = .{};
        return self;
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const seq = read.seq;
        self.total_bases += seq.len;
        if (seq.len > self.max_len_seen) self.max_len_seen = seq.len;

        for (seq, 0..) |base, i| {
            if (i >= MAX_POS) break;
            switch (base) {
                'A', 'a' => {
                    self.a += 1;
                    self.pos_a[i] += 1;
                },
                'C', 'c' => {
                    self.c += 1;
                    self.pos_c[i] += 1;
                },
                'G', 'g' => {
                    self.g += 1;
                    self.pos_g[i] += 1;
                },
                'T', 't' => {
                    self.t += 1;
                    self.pos_t[i] += 1;
                },
                else => {
                    self.n += 1;
                    self.pos_n[i] += 1;
                },
            }
        }
        return true;
    }

    pub fn processBitplanes(ptr: *anyopaque, bps: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const fused = @constCast(bps).getFused(block.read_count);
        
        self.a += fused.a_count;
        self.c += fused.c_count;
        self.g += fused.g_count;
        self.t += fused.t_count;
        self.n += fused.n_count;
        self.total_bases += fused.total_bases;

        for (0..bps.max_read_len) |col| {
            if (col >= MAX_POS) break;
            const offset = col * bps.u64_per_col;
            const u64_count = (block.read_count + 63) / 64;
            
            var col_a: usize = 0;
            var col_c: usize = 0;
            var col_g: usize = 0;
            var col_t: usize = 0;
            var col_n: usize = 0;

            for (0..u64_count) |i| {
                col_a += @popCount(bps.plane_a[offset + i]);
                col_c += @popCount(bps.plane_c[offset + i]);
                col_g += @popCount(bps.plane_g[offset + i]);
                col_t += @popCount(bps.plane_t[offset + i]);
                col_n += @popCount(bps.plane_n[offset + i]);
            }
            
            self.pos_a[col] += col_a;
            self.pos_c[col] += col_c;
            self.pos_g[col] += col_g;
            self.pos_t[col] += col_t;
            self.pos_n[col] += col_n;
            
            if ((col_a | col_c | col_g | col_t | col_n) > 0) {
                if (col + 1 > self.max_len_seen) self.max_len_seen = col + 1;
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
        
        self.a += other.a;
        self.c += other.c;
        self.g += other.g;
        self.t += other.t;
        self.n += other.n;
        self.total_bases += other.total_bases;
        if (other.max_len_seen > self.max_len_seen) self.max_len_seen = other.max_len_seen;

        for (0..self.max_len_seen) |i| {
            self.pos_a[i] += other.pos_a[i];
            self.pos_c[i] += other.pos_c[i];
            self.pos_g[i] += other.pos_g[i];
            self.pos_t[i] += other.pos_t[i];
            self.pos_n[i] += other.pos_n[i];
        }
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("\n[Nucleotide Composition]\n", .{}) catch {};
        writer.print("  A: {d} ({d:.2}%)\n", .{ self.a, if (self.total_bases > 0) @as(f64, @floatFromInt(self.a)) * 100.0 / @as(f64, @floatFromInt(self.total_bases)) else 0.0 }) catch {};
        writer.print("  C: {d} ({d:.2}%)\n", .{ self.c, if (self.total_bases > 0) @as(f64, @floatFromInt(self.c)) * 100.0 / @as(f64, @floatFromInt(self.total_bases)) else 0.0 }) catch {};
        writer.print("  G: {d} ({d:.2}%)\n", .{ self.g, if (self.total_bases > 0) @as(f64, @floatFromInt(self.g)) * 100.0 / @as(f64, @floatFromInt(self.total_bases)) else 0.0 }) catch {};
        writer.print("  T: {d} ({d:.2}%)\n", .{ self.t, if (self.total_bases > 0) @as(f64, @floatFromInt(self.t)) * 100.0 / @as(f64, @floatFromInt(self.total_bases)) else 0.0 }) catch {};
        writer.print("  N: {d} ({d:.2}%)\n", .{ self.n, if (self.total_bases > 0) @as(f64, @floatFromInt(self.n)) * 100.0 / @as(f64, @floatFromInt(self.total_bases)) else 0.0 }) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"nucleotide_composition\": {{\"a\": {d}, \"c\": {d}, \"g\": {d}, \"t\": {d}, \"n\": {d}, \"total_bases\": {d}}}", .{ self.a, self.c, self.g, self.t, self.n, self.total_bases });
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
