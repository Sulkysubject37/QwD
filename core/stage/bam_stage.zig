const std = @import("std");
const bam_reader = @import("bam_reader");

/// BAM Stage abstraction.
pub const BamStage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        process: *const fn (ptr: *anyopaque, record: *const bam_reader.AlignmentRecord) anyerror!void,
        finalize: *const fn (ptr: *anyopaque) anyerror!void,
        report: *const fn (ptr: *anyopaque, writer: *std.Io.Writer) void,
        reportJson: *const fn (ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void,
    };

    pub fn processRecord(self: BamStage, record: *const bam_reader.AlignmentRecord) !void {
        return self.vtable.process(self.ptr, record);
    }

    pub fn finalize(self: BamStage) !void {
        return self.vtable.finalize(self.ptr);
    }

    pub fn report(self: BamStage, writer: *std.Io.Writer) void {
        return self.vtable.report(self.ptr, writer);
    }

    pub fn reportJson(self: BamStage, writer: *std.Io.Writer) !void {
        return self.vtable.reportJson(self.ptr, writer);
    }
};
