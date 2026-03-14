const std = @import("std");
const parser = @import("parser");

/// Stage abstraction used by the scheduler.
pub const Stage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        process: *const fn (ptr: *anyopaque, read: *parser.Read) anyerror!bool,
        finalize: *const fn (ptr: *anyopaque) anyerror!void,
        report: *const fn (ptr: *anyopaque, writer: std.io.AnyWriter) void,
        merge: ?*const fn (ptr: *anyopaque, other: *anyopaque) anyerror!void = null,
    };

    pub fn process(self: Stage, read: *parser.Read) !bool {
        return self.vtable.process(self.ptr, read);
    }

    pub fn finalize(self: Stage) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn report(self: Stage, writer: std.io.AnyWriter) void {
        return self.vtable.report(self.ptr, writer);
    }

    pub fn merge(self: Stage, other: Stage) !void {
        if (self.vtable.merge) |merge_fn| {
            try merge_fn(self.ptr, other.ptr);
        }
    }
};
