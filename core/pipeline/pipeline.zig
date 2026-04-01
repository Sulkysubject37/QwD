const std = @import("std");
const scheduler_mod = @import("scheduler");
const parallel_scheduler = @import("parallel_scheduler");
const stage_mod = @import("stage");
const read_batch = @import("read_batch");
const simd_ops = @import("simd_ops");
const base_decode = @import("base_decode");
const memory_manager = @import("memory_manager");
const stage_interface = @import("stage");
const pipeline_config = @import("pipeline_config");
const mode_mod = @import("mode");
const block_reader = @import("block_reader");
const parser_mod = @import("parser");
const fastq_block = @import("fastq_block");
const bitplanes_mod = @import("bitplanes");

pub const Pipeline = struct {
    arena: std.heap.ArenaAllocator,
    scheduler: ?scheduler_mod.Scheduler = null,
    parallel_scheduler: ?parallel_scheduler.ParallelScheduler = null,
    stage_names: std.ArrayList([]const u8),
    stages: std.ArrayList(stage_mod.Stage),
    config: ?pipeline_config.PipelineConfig = null,
    mode: mode_mod.Mode = .EXACT,
    gzip_mode: mode_mod.GzipMode = .AUTO,
    read_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: ?pipeline_config.PipelineConfig) Pipeline {
        return Pipeline{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .stage_names = std.ArrayList([]const u8).init(allocator),
            .stages = std.ArrayList(stage_mod.Stage).init(allocator),
            .config = config,
            .mode = if (config) |c| c.mode else .EXACT,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        if (self.parallel_scheduler) |*ps| ps.deinit();
        if (self.scheduler) |*s| s.deinit();
        self.stages.deinit();
        self.stage_names.deinit();
        self.arena.deinit();
    }

    pub fn addStage(self: *Pipeline, name: []const u8) !void {
        try self.stage_names.append(try self.arena.allocator().dupe(u8, name));
    }

    pub fn setupSchedulers(self: *Pipeline, num_threads: usize) !void {
        if (num_threads > 1) {
            self.parallel_scheduler = parallel_scheduler.ParallelScheduler.init(
                self.arena.child_allocator,
                num_threads,
            );
            for (self.stage_names.items) |name| {
                const stage = try self.createStageInstance(self.arena.allocator(), name);
                try self.stages.append(stage);
            }
        } else {
            self.scheduler = scheduler_mod.Scheduler.init(self.arena.allocator());
            for (self.stage_names.items) |name| {
                const stage = try self.createStageInstance(self.arena.allocator(), name);
                try self.scheduler.?.registerStage(stage);
                try self.stages.append(stage);
            }
        }
    }

    pub fn run(self: *Pipeline, input_file: std.fs.File, is_gz: bool) !void {
        const allocator = self.arena.allocator();
        var fr = input_file.reader();

        if (self.parallel_scheduler) |*ps| {
            if (is_gz and (self.gzip_mode == .NATIVE or self.gzip_mode == .AUTO)) {
                // Check if BGZF
                try input_file.seekTo(0);
                const is_bgzf = @import("bgzf_native_reader").BgzfNativeReader.isBgzf(input_file.reader());
                try input_file.seekTo(0);

                if (is_bgzf) {
                    var native_reader = try @import("bgzf_native_reader").BgzfNativeReader.init(allocator, input_file.reader().any());
                    defer native_reader.deinit();
                    var chunk_builder = @import("bgzf_chunk_builder").BgzfChunkBuilder.init(allocator, &native_reader);
                    try ps.run_chunked(&chunk_builder, self);
                    return;
                }
            }

            var parser = if (is_gz)
                try parser_mod.FastqParser.initGzip(allocator, fr.any(), 1024 * 1024, self.gzip_mode)
            else if (self.mode == .APPROX)
                try parser_mod.FastqParser.initMmap(allocator, input_file)
            else
                try parser_mod.FastqParser.init(allocator, fr.any(), 1024 * 1024);
            defer parser.deinit();

            try ps.run_parallel(&parser, self);
        } else if (self.scheduler) |*s| {
            var parser = if (is_gz)
                try parser_mod.FastqParser.initGzip(allocator, fr.any(), 1024 * 1024, self.gzip_mode)
            else if (self.mode == .APPROX)
                try parser_mod.FastqParser.initMmap(allocator, input_file)
            else
                try parser_mod.FastqParser.init(allocator, fr.any(), 1024 * 1024);
            defer parser.deinit();

            const record_buffer = try allocator.alloc(u8, 1024 * 1024);
            defer allocator.free(record_buffer);
            while (try parser.next(record_buffer)) |read| {
                try s.process(read);
            }
            self.read_count = s.read_count;
            try s.finalize();
        }
    }

    pub fn run_chunked(self: *Pipeline, chunk_builder_ptr: anytype) !void {
        if (self.parallel_scheduler) |*ps| {
            try ps.run_chunked(chunk_builder_ptr, self);
        } else {
            // Sequential fallback for chunked
            const dummy_br = try self.arena.allocator().create(block_reader.BlockReader);
            var fbs = std.io.fixedBufferStream(@constCast(&[_]u8{}));
            dummy_br.* = try block_reader.BlockReader.init(self.arena.allocator(), fbs.reader().any(), 1024);
            var local_parser = parser_mod.FastqParser{
                .reader = dummy_br,
                .allocator = self.arena.child_allocator,
            };

            while (try chunk_builder_ptr.nextChunk()) |chunk| {
                local_parser.reader.buffer = @constCast(chunk);
                local_parser.reader.pos = 0;
                local_parser.reader.end = chunk.len;

                const record_buffer = try self.arena.allocator().alloc(u8, 1024 * 1024);
                while (try local_parser.next(record_buffer)) |read| {
                    if (self.scheduler) |*s| try s.process(read);
                    self.read_count += 1;
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
        }
        for (self.stages.items) |stage| {
            stage.report(writer);
        }
    }

    pub fn reportJson(self: *Pipeline, writer: std.io.AnyWriter) !void {
        try writer.print(
            \\{{
            \\  "version": "1.1.0",
            \\  "read_count": {d},
            \\  "stages": {{
        , .{self.read_count});

        for (self.stages.items, 0..) |stage, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\n");
            try stage.reportJson(writer);
        }

        try writer.writeAll("\n  }\n}\n");
    }

    pub fn reportJsonAlloc(self: *Pipeline, allocator: std.mem.Allocator) ![*:0]const u8 {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();
        try self.reportJson(list.writer().any());
        return try list.toOwnedSliceSentinel(0);
    }

    pub fn createStageInstance(self: *Pipeline, allocator: std.mem.Allocator, name: []const u8) !stage_mod.Stage {
        _ = self;
        if (std.mem.eql(u8, name, "basic_stats") or std.mem.eql(u8, name, "basic-stats")) {
            const s = try @import("basic_stats").BasicStatsStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "nucleotide_composition") or std.mem.eql(u8, name, "nucleotide-composition")) {
            const s = try @import("nucleotide_composition").NucleotideCompositionStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "qc")) {
            const s = try @import("qc").QcStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "gc_distribution") or std.mem.eql(u8, name, "gc-distribution") or std.mem.eql(u8, name, "gc")) {
            const s = try @import("gc_distribution").GcDistributionStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "length_distribution") or std.mem.eql(u8, name, "length-distribution")) {
            const s = try @import("qc_length_dist").LengthDistributionStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "n_statistics") or std.mem.eql(u8, name, "n50")) {
            const s = try @import("n_statistics").NStatisticsStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "entropy") or std.mem.eql(u8, name, "qc_entropy")) {
            const s = try @import("qc_entropy").EntropyStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "kmer_spectrum") or std.mem.eql(u8, name, "kmer-spectrum") or std.mem.eql(u8, name, "kmer")) {
            const s = try @import("kmer_spectrum").KmerSpectrumStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "overrepresented")) {
            const s = try @import("overrepresented").OverrepresentedStage.init(allocator);
            s.mode = self.mode;
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "duplication")) {
            const s = try @import("duplication").DuplicationStage.init(allocator);
            s.mode = self.mode;
            if (self.mode == .APPROX) {
                // Initialize 128MB Bloom Filter for duplication detection
                s.bloom = try @import("bloom_filter").BloomFilter.init(allocator, 128 * 1024 * 1024);
            }
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "adapter_detect") or std.mem.eql(u8, name, "adapter-detect")) {
            const s = try @import("qc_adapter_detect").AdapterDetectionStage.init(allocator);
            return @constCast(s).stage();
        }
        if (std.mem.eql(u8, name, "per_base_quality") or std.mem.eql(u8, name, "quality-decay") or std.mem.eql(u8, name, "quality_decay")) {
            const s = try @import("per_base_quality").PerBaseQualityStage.init(allocator);
            return @constCast(s).stage();
        }
        return error.UnknownStage;
    }
};
