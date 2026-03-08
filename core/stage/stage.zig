const std = @import("std");
const parser = @import("parser");

/// Stage abstraction used by the scheduler.
pub const Stage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// process(ptr, read) -> bool
        /// true  -> continue processing
        /// false -> discard read
        process: *const fn (ptr: *anyopaque, read: *parser.Read) anyerror!bool,
        finalize: *const fn (ptr: *anyopaque) anyerror!void,
        report: *const fn (ptr: *anyopaque) void,
    };

    pub fn process(self: Stage, read: *parser.Read) !bool {
        return self.vtable.process(self.ptr, read);
    }

    pub fn finalize(self: Stage) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn report(self: Stage) void {
        return self.vtable.report(self.ptr);
    }
};
