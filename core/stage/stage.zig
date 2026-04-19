const std = @import("std");
const parser = @import("parser");
const bitplanes = @import("bitplanes");
const fastq_block = @import("fastq_block");

/// Generic Stage abstraction for Phase Q.
/// This interface is pointer-stable and avoids circular dependencies.
pub const Stage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        process: *const fn (ptr: *anyopaque, read: *const parser.Read) anyerror!bool,
        finalize: *const fn (ptr: *anyopaque) anyerror!void,
        report: *const fn (ptr: *anyopaque, writer: *std.Io.Writer) void,
        reportJson: *const fn (ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void,
        merge: *const fn (ptr: *anyopaque, other_ptr: *anyopaque) anyerror!void,
        clone: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!*anyopaque,
        
        /// Optional high-performance SIMD path
        processBitplanes: ?*const fn (ptr: *anyopaque, bp: *const bitplanes.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool = null,
    };

    pub fn processRead(self: Stage, read: *const parser.Read) !bool {
        return self.vtable.process(self.ptr, read);
    }

    pub fn finalize(self: Stage) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn report(self: Stage, writer: *std.Io.Writer) void {
        self.vtable.report(self.ptr, writer);
    }

    pub fn reportJson(self: Stage, writer: *std.Io.Writer) !void {
        return self.vtable.reportJson(self.ptr, writer);
    }

    pub fn merge(self: Stage, other: Stage) !void {
        return self.vtable.merge(self.ptr, other.ptr);
    }

    pub fn clone(self: Stage, allocator: std.mem.Allocator) !Stage {
        const new_ptr = try self.vtable.clone(self.ptr, allocator);
        return Stage{
            .ptr = new_ptr,
            .vtable = self.vtable,
        };
    }
};
