const std = @import("std");
const Reader = @import("reader_interface").Reader;
const stage_mod = @import("stage");

pub const Scheduler = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addStage: *const fn (ctx: *anyopaque, stage: stage_mod.Stage) anyerror!void,
        run: *const fn (ctx: *anyopaque, reader: Reader) anyerror!void,
        finalize: *const fn (ctx: *anyopaque) anyerror!void,
        getReadCount: *const fn (ctx: *anyopaque) usize,
        setTelemetry: *const fn (ctx: *anyopaque, hook: *anyopaque) void,
        deinit: *const fn (ctx: *anyopaque) void,
    };

    pub fn addStage(self: Scheduler, stage: stage_mod.Stage) !void {
        return self.vtable.addStage(self.ptr, stage);
    }

    pub fn run(self: Scheduler, reader: Reader) !void {
        return self.vtable.run(self.ptr, reader);
    }

    pub fn finalize(self: Scheduler) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn getReadCount(self: Scheduler) usize {
        return self.vtable.getReadCount(self.ptr);
    }

    pub fn setTelemetry(self: Scheduler, hook: *anyopaque) void {
        return self.vtable.setTelemetry(self.ptr, hook);
    }

    pub fn deinit(self: Scheduler) void {
        return self.vtable.deinit(self.ptr);
    }
};
