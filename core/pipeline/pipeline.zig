const std = @import("std");
const mode_mod = @import("mode");
const pipeline_config = @import("pipeline_config");
const stage_mod = @import("stage");
const scheduler_mod = @import("scheduler");
const parallel_scheduler = @import("parallel_scheduler");

pub const Pipeline = struct {
    arena: std.heap.ArenaAllocator,
    sys_allocator: std.mem.Allocator,
    scheduler: ?scheduler_mod.Scheduler = null,
    parallel_scheduler: ?parallel_scheduler.ParallelScheduler = null,
    stage_names: std.ArrayList([]const u8),
    stages: std.ArrayList(stage_mod.Stage),
    config: pipeline_config.PipelineConfig,
    mode: mode_mod.Mode = .exact,
    gzip_mode: mode_mod.GzipMode = .auto,
    read_count: usize = 0,
    integrity_violations: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: pipeline_config.PipelineConfig) Pipeline {
        return Pipeline{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .sys_allocator = allocator,
            .stage_names = std.ArrayList([]const u8).empty,
            .stages = std.ArrayList(stage_mod.Stage).empty,
            .config = config,
            .mode = config.mode,
            .gzip_mode = config.gzip_mode,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        if (self.parallel_scheduler) |*ps| ps.deinit();
        if (self.scheduler) |*s| s.deinit();
        self.stage_names.deinit(self.sys_allocator);
        self.stages.deinit(self.sys_allocator);
        self.arena.deinit();
    }

    pub fn addDefaultStages(self: *Pipeline) !void {
        const allocator = self.arena.allocator();
        
        const default_stages = [_][]const u8{ 
            "basic_stats", 
            "gc_distribution", 
            "n_statistics", 
            "length_distribution", 
            "duplication",
            "trim",
            "filter",
            "quality_dist",
            "kmer_spectrum",
            "taxed",
            "overrepresented"
        };

        for (default_stages) |name| {
            try self.stage_names.append(self.sys_allocator, name);
            const s = try self.createStageInstance(allocator, name);
            try self.stages.append(self.sys_allocator, s);
            
            if (self.parallel_scheduler) |*ps| {
                try ps.addStage(s);
            }
        }
    }

    pub fn run(self: *Pipeline, input_file: std.Io.File, io: std.Io) !void {
        if (self.config.threads > 1 and self.parallel_scheduler == null) {
            self.parallel_scheduler = try parallel_scheduler.ParallelScheduler.init(self.sys_allocator, self.config.threads, io);
            // Re-add stages to scheduler
            for (self.stages.items) |s| {
                try self.parallel_scheduler.?.addStage(s);
            }
        }

        if (self.parallel_scheduler) |*ps| {
            try ps.run(input_file, self);
        } else {
            try self.runSerial(input_file, io);
        }
    }

    fn runSerial(self: *Pipeline, input_file: std.Io.File, io: std.Io) !void {
        std.debug.print("[Pipeline] Initializing FastqParser...\n", .{});
        var p = try @import("parser").FastqParser.initWithFile(self.sys_allocator, input_file, io, 65536);
        defer p.deinit();
        var buf: [65536]u8 = undefined;
        std.debug.print("[Pipeline] Starting read loop...\n", .{});
        while (try p.next(&buf)) |read| {
            for (self.stages.items) |stage| {
                _ = try stage.processRead(&read);
            }
            self.read_count += 1;
        }
        std.debug.print("[Pipeline] Finished read loop. Total reads: {d}\n", .{self.read_count});
    }

    pub fn finalize(self: *Pipeline) !void {
        if (self.parallel_scheduler) |*ps| {
            try ps.finalize();
        } else {
            for (self.stages.items) |stage| {
                try stage.finalize();
            }
        }
    }

    pub fn report(self: *Pipeline, writer: *std.Io.Writer) void {
        if (self.parallel_scheduler) |*ps| {
            ps.report(writer);
        } else {
            for (self.stages.items) |stage| {
                stage.report(writer);
            }
        }
    }

    pub fn reportJson(self: *Pipeline, writer: *std.Io.Writer) anyerror!void {
        const thread_count = if (self.parallel_scheduler) |ps| ps.num_threads else 1;
        try writer.print(
            \\{{
            \\  "version": "1.3.0",
            \\  "thread_count": {d},
            \\  "read_count": {d},
            \\  "stages": {{
        , .{ thread_count, self.read_count });

        for (self.stages.items, 0..) |stage, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n    ");
            try stage.reportJson(writer);
        }

        try writer.writeAll("\n    }"); // Close stages object
        try writer.writeAll("\n}\n"); // Close root object
    }

    pub fn reportJsonAlloc(self: *Pipeline, allocator: std.mem.Allocator, io: std.Io) ![*:0]const u8 {
        _ = io;
        var list = std.ArrayList(u8).empty;
        errdefer list.deinit(allocator);
        var aw = std.Io.Writer.Allocating.fromArrayList(allocator, &list);
        try self.reportJson(&aw.writer);
        var result_list = aw.toArrayList();
        return try result_list.toOwnedSliceSentinel(allocator, 0);
    }

    pub fn createStageInstance(self: *Pipeline, allocator: std.mem.Allocator, name: []const u8) !stage_mod.Stage {
        const child_allocator = allocator;
        if (std.mem.eql(u8, name, "basic_stats")) {
            const s = try @import("basic_stats").BasicStatsStage.init(child_allocator);
            return s.stage();
        }
        if (std.mem.eql(u8, name, "gc_distribution") or std.mem.eql(u8, name, "gc")) {
            const s = try child_allocator.create(@import("gc_distribution").GcdistributionStage);
            s.* = .{};
            return s.stage();
        }
        if (std.mem.eql(u8, name, "n_statistics")) {
            const s = try child_allocator.create(@import("n_statistics").NStatisticsStage);
            s.* = @import("n_statistics").NStatisticsStage.init();
            return s.stage();
        }
        if (std.mem.eql(u8, name, "length_distribution") or std.mem.eql(u8, name, "qc_length_dist")) {
            const s = try child_allocator.create(@import("qc_length_dist").LengthDistributionStage);
            s.* = @import("qc_length_dist").LengthDistributionStage.init(child_allocator);
            return s.stage();
        }
        if (std.mem.eql(u8, name, "duplication")) {
            const s = try child_allocator.create(@import("duplication").DuplicationStage);
            s.* = @import("duplication").DuplicationStage.init(child_allocator);
            return s.stage();
        }
        if (std.mem.eql(u8, name, "trim")) {
            const s = try child_allocator.create(@import("trim").TrimStage);
            s.* = @import("trim").TrimStage.init(self.config.adapter_sequence, self.config.trim_front, self.config.trim_tail);
            return s.stage();
        }
        if (std.mem.eql(u8, name, "filter")) {
            const s = try child_allocator.create(@import("filter").FilterStage);
            s.* = @import("filter").FilterStage.init(self.config.min_quality);
            return s.stage();
        }
        if (std.mem.eql(u8, name, "quality_dist") or std.mem.eql(u8, name, "per_base_quality") or std.mem.eql(u8, name, "per-base-quality")) {
            const s = try child_allocator.create(@import("per_base_quality").PerbasequalityStage);
            s.* = .{};
            return s.stage();
        }
        if (std.mem.eql(u8, name, "kmer_spectrum")) {
            const s = try child_allocator.create(@import("kmer_spectrum").KmerSpectrumStage);
            s.* = @import("kmer_spectrum").KmerSpectrumStage.init(child_allocator, 11);
            return s.stage();
        }
        if (std.mem.eql(u8, name, "taxed")) {
            const s = try child_allocator.create(@import("taxed").TaxedStage);
            s.* = try @import("taxed").TaxedStage.init(child_allocator);
            return s.stage();
        }
        if (std.mem.eql(u8, name, "overrepresented")) {
            const s = try child_allocator.create(@import("overrepresented").OverrepresentedStage);
            s.* = @import("overrepresented").OverrepresentedStage.init(child_allocator);
            return s.stage();
        }
        return error.StageNotFound;
    }
};
