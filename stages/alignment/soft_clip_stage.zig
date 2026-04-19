const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");

pub const SoftclipStage = struct {
    pub fn process(ptr: *anyopaque, record: *const bam_reader.AlignmentRecord) anyerror!void { 
        _ = ptr; _ = record;
    }
    pub fn finalize(ptr: *anyopaque) anyerror!void {
        _ = ptr;
    }
    pub fn report(ptr: *anyopaque, writer: *std.Io.Writer) void {
        _ = ptr; _ = writer;
    }
    pub fn reportJson(ptr: *anyopaque, writer: *std.Io.Writer) anyerror!void {
        _ = ptr;
        try writer.writeAll("{}");
    }

    pub fn stage(self: *@This()) bam_stage.BamStage {
        return .{
            .ptr = self,
            .vtable = &VTABLE,
        };
    }
};

const VTABLE = bam_stage.BamStage.VTable{
    .process = SoftclipStage.process,
    .finalize = SoftclipStage.finalize,
    .report = SoftclipStage.report,
    .reportJson = SoftclipStage.reportJson,
};
