const std = @import("std");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");

pub const StageTag = enum {
    adapter_detection,
    basic_stats,
    duplication,
    entropy,
    gc_distribution,
    kmer_spectrum,
    length_distribution,
    n_statistics,
    nucleotide_composition,
    overrepresented,
    per_base_quality,
    quality_dist,
    taxed,
};

/// The Sovereign Stage Interface
pub const Stage = struct {
    ptr: *anyopaque,
    tag: StageTag,
    vtable: *const VTable,

    pub const VTable = struct {
        processBitplanes: *const fn (ctx: *anyopaque, bp: *const bitplanes.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool,
        finalize: *const fn (ctx: *anyopaque) anyerror!void,
        // TYPE AGNOSTIC REPORTING: The stage must know how to cast this back.
        reportJson: *const fn (ctx: *anyopaque, writer: *anyopaque) anyerror!void,
        deinit: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,
    };

    pub fn init(ptr: *anyopaque, tag: StageTag, vtable: *const VTable) Stage {
        return .{ .ptr = ptr, .tag = tag, .vtable = vtable };
    }

    pub fn processBitplanes(self: Stage, bp: *const bitplanes.BitplaneCore, block: *const fastq_block.FastqColumnBlock) !bool {
        return self.vtable.processBitplanes(self.ptr, bp, block);
    }

    pub fn finalize(self: Stage) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn reportJson(self: Stage, writer: anytype) !void {
        return self.vtable.reportJson(self.ptr, @constCast(@ptrCast(writer)));
    }

    pub fn deinit(self: Stage, allocator: std.mem.Allocator) void {
        return self.vtable.deinit(self.ptr, allocator);
    }
};
