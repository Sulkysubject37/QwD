const std = @import("std");
const bam_scheduler_mod = @import("bam_scheduler");
const bam_stage_mod = @import("bam_stage");
const bam_reader_mod = @import("bam_reader");

const alignment_stats_mod = @import("alignment_stats");
const mapq_dist_mod = @import("mapq_dist");
const insert_size_mod = @import("insert_size");
const coverage_mod = @import("coverage");
const error_rate_mod = @import("error_rate");
const soft_clip_mod = @import("soft_clip");

pub const BamPipeline = struct {
    scheduler: bam_scheduler_mod.BamScheduler,
    arena: std.heap.ArenaAllocator,

    pub fn init(child_allocator: std.mem.Allocator) BamPipeline {
        return BamPipeline{
            .scheduler = bam_scheduler_mod.BamScheduler.init(child_allocator),
            .arena = std.heap.ArenaAllocator.init(child_allocator),
        };
    }

    pub fn deinit(self: *BamPipeline) void {
        self.scheduler.deinit();
        self.arena.deinit();
    }

    pub fn addDefaultStages(self: *BamPipeline) !void {
        const allocator = self.arena.allocator();

        var s1 = try allocator.create(alignment_stats_mod.AlignmentStatsStage);
        s1.* = .{};
        try self.scheduler.registerStage(s1.stage());

        var s2 = try allocator.create(mapq_dist_mod.MapqDistributionStage);
        s2.* = .{};
        try self.scheduler.registerStage(s2.stage());

        var s3 = try allocator.create(insert_size_mod.InsertSizeStage);
        s3.* = .{};
        try self.scheduler.registerStage(s3.stage());

        var s4 = try allocator.create(coverage_mod.CoverageStage);
        s4.* = coverage_mod.CoverageStage.init(3000000000);
        try self.scheduler.registerStage(s4.stage());

        var s5 = try allocator.create(error_rate_mod.ErrorRateStage);
        s5.* = .{};
        try self.scheduler.registerStage(s5.stage());

        var s6 = try allocator.create(soft_clip_mod.SoftClipStage);
        s6.* = .{};
        try self.scheduler.registerStage(s6.stage());
    }

    pub fn run(self: *BamPipeline, record: bam_reader_mod.AlignmentRecord) !void {
        try self.scheduler.process(record);
    }

    pub fn finalize(self: *BamPipeline) !void {
        try self.scheduler.finalize();
    }

    pub fn report(self: *BamPipeline, writer: std.io.AnyWriter) !void {
        try writer.print("\nQwD BAM Analytics Summary\n", .{});
        try writer.print("=========================\n", .{});
        self.scheduler.report(writer);
        try writer.print("=========================\n", .{});
    }

    pub fn reportJson(self: *BamPipeline, writer: std.io.AnyWriter) !void {
        try writer.print(
            \\{{
            \\  "version": "1.1.0",
            \\  "record_count": {d},
            \\  "stages": {{
        , .{self.scheduler.record_count});

        for (self.scheduler.stages.items, 0..) |stage, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n");
            try stage.reportJson(writer);
        }

        try writer.writeAll("\n  }\n}\n");
    }

    pub fn reportJsonAlloc(self: *BamPipeline, allocator: std.mem.Allocator) ![*:0]const u8 {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();
        try self.reportJson(list.writer().any());
        return try list.toOwnedSliceSentinel(0);
    }
};
