const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");

pub const BamPipeline = struct {
    allocator: std.mem.Allocator,
    stages: std.ArrayList(bam_stage.BamStage),
    record_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) BamPipeline {
        return .{
            .allocator = allocator,
            .stages = std.ArrayList(bam_stage.BamStage).empty,
        };
    }

    pub fn deinit(self: *BamPipeline) void {
        self.stages.deinit(self.allocator);
    }

    pub fn addStage(self: *BamPipeline, stage: bam_stage.BamStage) !void {
        try self.stages.append(self.allocator, stage);
    }

    pub fn run(self: *BamPipeline, file: std.Io.File, io: std.Io) !void {
        var reader = try bam_reader.BamReader.init(self.allocator, file, io);
        defer reader.deinit();

        while (try reader.next()) |record| {
            for (self.stages.items) |stage| {
                try stage.processRecord(&record);
            }
            self.record_count += 1;
        }
    }

    pub fn finalize(self: *BamPipeline) !void {
        for (self.stages.items) |stage| {
            try stage.finalize();
        }
    }

    pub fn report(self: *BamPipeline, writer: *std.Io.Writer) void {
        for (self.stages.items) |stage| {
            stage.report(writer);
        }
    }

    pub fn reportJson(self: *BamPipeline, writer: *std.Io.Writer) anyerror!void {
        try writer.print(
            \\{{
            \\  "version": "1.2.0-secured",
            \\  "read_count": {d},
            \\  "stages": {{
        , .{self.record_count});

        for (self.stages.items, 0..) |stage, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n    ");
            try stage.reportJson(writer);
        }

        try writer.writeAll("\n  }\n}\n");
    }

    pub fn reportJsonAlloc(self: *BamPipeline, allocator: std.mem.Allocator, io: std.Io) ![*:0]const u8 {
        _ = io;
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        var aw = std.Io.Writer.Allocating.fromArrayList(allocator, &list);
        try self.reportJson(&aw.writer);
        var result_list = aw.toArrayList();
        return try result_list.toOwnedSliceSentinel(allocator, 0);
    }
};
