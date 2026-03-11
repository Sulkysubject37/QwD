const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");

pub const BamScheduler = struct {
    record_count: usize = 0,
    stages: std.ArrayList(bam_stage.BamStage),

    pub fn init(allocator: std.mem.Allocator) BamScheduler {
        return BamScheduler{
            .stages = std.ArrayList(bam_stage.BamStage).init(allocator),
        };
    }

    pub fn deinit(self: *BamScheduler) void {
        self.stages.deinit();
    }

    pub fn registerStage(self: *BamScheduler, stage: bam_stage.BamStage) !void {
        try self.stages.append(stage);
    }

    pub fn process(self: *BamScheduler, record: bam_reader.AlignmentRecord) !void {
        self.record_count += 1;
        var r = record;
        for (self.stages.items) |stage| {
            if (!(try stage.process(&r))) break;
        }
    }

    pub fn finalize(self: *BamScheduler) !void {
        for (self.stages.items) |stage| {
            try stage.finalize();
        }
    }

    pub fn report(self: *BamScheduler, writer: std.io.AnyWriter) void {
        for (self.stages.items) |stage| {
            stage.report(writer);
        }
    }
};
