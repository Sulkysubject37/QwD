const std = @import("std");
const mode_mod = @import("mode");
const pipeline_config = @import("pipeline_config");
const stage_mod = @import("stage");
const parser_mod = @import("parser");
const reader_interface = @import("reader_interface");
const scheduler_interface = @import("scheduler_interface");

pub const Reader = reader_interface.Reader;

// Verified Symbols
const BasicStatsStage = @import("basic_stats").BasicStatsStage;
const GcdistributionStage = @import("gc_distribution").GcdistributionStage;
const NStatisticsStage = @import("n_statistics").NStatisticsStage;
const LengthDistributionStage = @import("length_distribution").LengthDistributionStage;
const QualitydistStage = @import("quality_dist").QualitydistStage;
const NucleotidecompositionStage = @import("nucleotide_composition").NucleotidecompositionStage;

pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    config: pipeline_config.PipelineConfig,
    stages: [32]stage_mod.Stage = undefined,
    stage_count: usize = 0,
    read_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: pipeline_config.PipelineConfig) Pipeline {
        return .{
            .allocator = allocator,
            .config = config,
            .stage_count = 0,
            .read_count = 0,
        };
    }

    pub fn addStage(self: *Pipeline, stage: stage_mod.Stage) void {
        if (self.stage_count < 32) {
            self.stages[self.stage_count] = stage;
            self.stage_count += 1;
        }
    }

    pub fn addDefaultStages(self: *Pipeline) !void {
        const bs = try self.allocator.create(BasicStatsStage);
        bs.* = .{};
        self.addStage(bs.stage());

        const gc = try self.allocator.create(GcdistributionStage);
        gc.* = .{};
        self.addStage(gc.stage());

        const nst = try self.allocator.create(NStatisticsStage);
        nst.* = .{};
        self.addStage(nst.stage());
        
        const ld = try self.allocator.create(LengthDistributionStage);
        ld.* = .{};
        self.addStage(ld.stage());
        
        const qd = try self.allocator.create(QualitydistStage);
        qd.* = QualitydistStage.init();
        self.addStage(qd.stage());
        
        const nc = try self.allocator.create(NucleotidecompositionStage);
        nc.* = .{};
        self.addStage(nc.stage());
    }

    pub fn run(self: *Pipeline, reader: Reader, scheduler: scheduler_interface.Scheduler) !void {
        for (0..self.stage_count) |i| {
            try scheduler.addStage(self.stages[i]);
        }
        try scheduler.run(reader);
        self.read_count = scheduler.getReadCount();
    }

    pub fn finalize(self: *Pipeline) !void {
        for (0..self.stage_count) |i| {
            try self.stages[i].finalize();
        }
    }

    pub fn reportJson(self: *Pipeline, writer: anytype) !void {
        try writer.print("{{", .{});
        try writer.print("\"read_count\": {d}", .{self.read_count});
        for (0..self.stage_count) |i| {
            try writer.print(", ", .{});
            try self.stages[i].reportJson(writer);
        }
        try writer.print("}}", .{});
    }

    pub fn deinit(self: *Pipeline) void {
        for (0..self.stage_count) |i| {
            self.stages[i].deinit(self.allocator);
        }
    }
};
