const std = @import("std");
const parser = @import("parser");

/// Stage abstraction used by the scheduler.
pub const Stage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        process: *const fn (ptr: *anyopaque, read: *const parser.Read) anyerror!bool,
        processRawBatch: ?*const fn (ptr: *anyopaque, reads: []const parser.Read) anyerror!bool = null,
        processBlock: ?*const fn (ptr: *anyopaque, block: *const @import("fastq_block").FastqColumnBlock) anyerror!bool = null,
        processBitplanes: ?*const fn (ptr: *anyopaque, bitplanes: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) anyerror!bool = null,
        finalize: *const fn (ptr: *anyopaque) anyerror!void,
        report: *const fn (ptr: *anyopaque, writer: std.io.AnyWriter) void,
        reportJson: ?*const fn (ptr: *anyopaque, writer: std.io.AnyWriter) anyerror!void = null,
        merge: ?*const fn (ptr: *anyopaque, other: *anyopaque) anyerror!void = null,
    };

    pub fn process(self: Stage, read: *const parser.Read) !bool {
        return self.vtable.process(self.ptr, read);
    }

    pub fn processRawBatch(self: Stage, reads: []const parser.Read) !bool {
        if (self.vtable.processRawBatch) |pb| {
            return pb(self.ptr, reads);
        } else {
            // Fallback for stages that don't support raw batch processing yet
            for (reads) |*read| {
                if (!(try self.process(read))) return false;
            }
            return true;
        }
    }

    pub fn processBlock(self: Stage, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        if (self.vtable.processBlock) |pb| {
            return pb(self.ptr, block);
        } else {
            // Fallback for stages that don't support columnar block processing yet
            // This is a slow path, ideally all Phase Q stages should implement processBlock
            return true;
        }
    }

    pub fn processBitplanes(self: Stage, bitplanes: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool {
        if (self.vtable.processBitplanes) |pb| {
            return pb(self.ptr, bitplanes, block);
        } else {
            // Fallback to processBlock if bitplanes not supported
            return self.processBlock(block);
        }
    }

    pub fn finalize(self: Stage) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn report(self: Stage, writer: std.io.AnyWriter) void {
        return self.vtable.report(self.ptr, writer);
    }

    pub fn reportJson(self: Stage, writer: std.io.AnyWriter) !void {
        if (self.vtable.reportJson) |rj| {
            try rj(self.ptr, writer);
        } else {
            try writer.writeAll("{}");
        }
    }

    pub fn merge(self: Stage, other: Stage) !void {
        if (self.vtable.merge) |merge_fn| {
            try merge_fn(self.ptr, other.ptr);
        }
    }
};
