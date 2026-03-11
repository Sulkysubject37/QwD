const std = @import("std");
const bam_reader = @import("bam_reader");

pub const BamStage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        process: *const fn (ptr: *anyopaque, record: *bam_reader.AlignmentRecord) anyerror!bool,
        finalize: *const fn (ptr: *anyopaque) anyerror!void,
        report: *const fn (ptr: *anyopaque, writer: std.io.AnyWriter) void,
    };

    pub fn process(self: BamStage, record: *bam_reader.AlignmentRecord) !bool {
        return self.vtable.process(self.ptr, record);
    }

    pub fn finalize(self: BamStage) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn report(self: BamStage, writer: std.io.AnyWriter) void {
        return self.vtable.report(self.ptr, writer);
    }
};
