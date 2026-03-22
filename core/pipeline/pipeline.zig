const std = @import("std");
const scheduler_mod = @import("scheduler");
const parallel_scheduler = @import("parallel_scheduler");
const read_batch = @import("read_batch");
const simd_ops = @import("simd_ops");
const base_decode = @import("base_decode");
const memory_manager = @import("memory_manager");
const stage_interface = @import("stage");
const parser_mod = @import("parser");
const block_reader = @import("block_reader");
const raw_batch = @import("raw_batch");
const chunk_builder = @import("chunk_builder");
const read_graph = @import("read_graph");
const prefetch = @import("prefetch");
const pipeline_config = @import("pipeline_config");
const mode_mod = @import("mode");

pub const Pipeline = struct {
    arena: std.heap.ArenaAllocator,
    scheduler: ?scheduler_mod.Scheduler = null,
    parallel_scheduler: ?parallel_scheduler.ParallelScheduler = null,
    stage_names: std.ArrayList([]const u8),
    config: ?pipeline_config.PipelineConfig = null,
    mode: mode_mod.Mode = .EXACT,

    pub fn init(allocator: std.mem.Allocator, config: ?pipeline_config.PipelineConfig) Pipeline {
        return Pipeline{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .stage_names = std.ArrayList([]const u8).init(allocator),
            .config = config,
            .mode = if (config) |c| c.mode else .EXACT,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        if (self.parallel_scheduler) |*ps| ps.deinit();
        if (self.scheduler) |*s| s.deinit();
        self.stage_names.deinit();
        self.arena.deinit();
    }

    pub fn addStage(self: *Pipeline, name: []const u8) !void {
        try self.stage_names.append(try self.arena.allocator().dupe(u8, name));
    }

    pub fn setupSchedulers(self: *Pipeline, num_threads: usize) !void {
        if (num_threads >= 1) {
            // Pass arena.child_allocator as sys_allocator so thread-local arenas
            // and bookkeeping use the raw, uncapped allocator (GPA), not the
            // GlobalAllocator with its memory cap. This prevents setup deadlock.
            self.parallel_scheduler = parallel_scheduler.ParallelScheduler.init(
                self.arena.allocator(),
                self.arena.child_allocator,
                num_threads,
            );
            for (self.stage_names.items) |name| {
                const stage = try self.createStageInstance(self.arena.allocator(), name);
                try self.parallel_scheduler.?.registerStage(stage);
            }
        } else {
            @panic("num_threads must be at least 1");
        }
    }

    pub fn createStageInstance(self: *Pipeline, allocator: std.mem.Allocator, name: []const u8) !stage_interface.Stage {
        if (std.mem.eql(u8, name, "qc")) {
            const qc = try allocator.create(@import("qc").QcStage);
            qc.* = @import("qc").QcStage{};
            return qc.stage();
        } else if (std.mem.eql(u8, name, "gc")) {
            const gc = try allocator.create(@import("gc").GcStage);
            gc.* = @import("gc").GcStage{};
            return gc.stage();
        } else if (std.mem.eql(u8, name, "basic-stats")) {
            const stage = try allocator.create(@import("basic_stats").BasicStatsStage);
            stage.* = @import("basic_stats").BasicStatsStage{};
            return stage.stage();
        } else if (std.mem.eql(u8, name, "per-base-quality")) {
            const stage = try allocator.create(@import("per_base_quality").PerBaseQualityStage);
            stage.* = @import("per_base_quality").PerBaseQualityStage{};
            return stage.stage();
        } else if (std.mem.eql(u8, name, "nucleotide-composition")) {
            const stage = try allocator.create(@import("nucleotide_composition").NucleotideCompositionStage);
            stage.* = @import("nucleotide_composition").NucleotideCompositionStage{};
            return stage.stage();
        } else if (std.mem.eql(u8, name, "gc-distribution")) {
            const stage = try allocator.create(@import("gc_distribution").GcDistributionStage);
            stage.* = @import("gc_distribution").GcDistributionStage{};
            return stage.stage();
        } else if (std.mem.eql(u8, name, "length-distribution")) {
            const stage = try allocator.create(@import("qc_length_dist").LengthDistributionStage);
            stage.* = @import("qc_length_dist").LengthDistributionStage{};
            return stage.stage();
        } else if (std.mem.eql(u8, name, "n-statistics")) {
            const stage = try allocator.create(@import("n_statistics").NStatisticsStage);
            stage.* = @import("n_statistics").NStatisticsStage{};
            return stage.stage();
        } else if (std.mem.eql(u8, name, "entropy")) {
            const stage = try allocator.create(@import("qc_entropy").EntropyStage);
            stage.* = @import("qc_entropy").EntropyStage{};
            return stage.stage();
        } else if (std.mem.eql(u8, name, "kmer-spectrum")) {
            const stage = try allocator.create(@import("kmer_spectrum").KmerSpectrumStage);
            stage.* = try @import("kmer_spectrum").KmerSpectrumStage.init(allocator);
            return stage.stage();
        } else if (std.mem.eql(u8, name, "overrepresented")) {
            const stage = try allocator.create(@import("overrepresented").OverrepresentedStage);
            stage.* = @import("overrepresented").OverrepresentedStage.init(allocator, self.mode == .FAST);
            return stage.stage();
        } else if (std.mem.eql(u8, name, "duplication")) {
            const stage = try allocator.create(@import("duplication").DuplicationStage);
            stage.* = @import("duplication").DuplicationStage.init(allocator, self.mode == .FAST);
            return stage.stage();
        } else if (std.mem.eql(u8, name, "adapter-detect")) {
            const stage = try allocator.create(@import("qc_adapter_detect").AdapterDetectionStage);
            stage.* = try @import("qc_adapter_detect").AdapterDetectionStage.init(allocator);
            return stage.stage();
        } else if (std.mem.eql(u8, name, "trim")) {
            const stage = try allocator.create(@import("trim").TrimStage);
            stage.* = @import("trim").TrimStage.init("AGATCGGAAGAGC");
            return stage.stage();
        } else if (std.mem.eql(u8, name, "filter")) {
            const stage = try allocator.create(@import("filter").FilterStage);
            stage.* = @import("filter").FilterStage.init(20.0);
            return stage.stage();
        } else if (std.mem.eql(u8, name, "kmer")) {
            const stage = try allocator.create(@import("kmer").KmerStage);
            stage.* = try @import("kmer").KmerStage.init(allocator, 5);
            return stage.stage();
        } else {
            return error.UnknownStage;
        }
    }

    pub fn run_chunked(self: *Pipeline, chunk_builder_ptr: anytype) !void {
        if (self.parallel_scheduler) |*ps| {
            try ps.run_chunked(chunk_builder_ptr, self);
        } else {
            // Sequential fallback
            const dummy_br = block_reader.BlockReader{
                .file = null,
                .buffer = &[_]u8{},
                .pos = 0,
                .end = 0,
                .mmap_handle = null,
                .is_mmap = true,
            };

            var local_parser = parser_mod.FastqParser{
                .br = dummy_br,
                .allocator = self.arena.child_allocator,
                .eof = false,
            };
            var dummy_out: [1]u8 = undefined;

            while (try chunk_builder_ptr.nextChunk()) |chunk| {
                local_parser.br.buffer = @constCast(chunk);
                local_parser.br.pos = 0;
                local_parser.br.end = chunk.len;
                local_parser.eof = false;

                while (true) {
                    var reads_array: [1024]parser_mod.Read = undefined;
                    var rc: usize = 0;
                    while (rc < 1024) {
                        if (try local_parser.next(&dummy_out)) |read| {
                            reads_array[rc] = read;
                            rc += 1;
                        } else break;
                    }
                    
                    if (rc == 0) break;
                    
                    if (self.scheduler) |*s| {
                        for (s.stages.items) |stage| {
                            _ = try stage.processRawBatch(reads_array[0..rc]);
                        }
                    }
                }
            }
        }
    }

    pub fn run_batches(self: *Pipeline, builder: anytype) !void {
        var batch = try read_batch.ReadBatch.init(self.arena.child_allocator, 1024);
        defer batch.deinit(self.arena.child_allocator);

        while (try builder.fillBatch(&batch)) {
            if (self.parallel_scheduler) |*ps| {
                // Not implemented for parallel_scheduler yet, use run_chunked
                _ = ps;
                return error.NotImplemented;
            } else if (self.scheduler) |*s| {
                for (0..batch.count) |i| {
                    try s.process(batch.reads[i]);
                }
            }
        }
    }

    pub fn finalize(self: *Pipeline) !void {
        if (self.parallel_scheduler) |*ps| {
            try ps.finalize();
        } else if (self.scheduler) |*s| {
            try s.finalize();
        }
    }

    pub fn report(self: *Pipeline, writer: std.io.AnyWriter) void {
        if (self.parallel_scheduler) |*ps| {
            ps.report(writer);
        } else if (self.scheduler) |*s| {
            s.report(writer);
        }
    }
};
