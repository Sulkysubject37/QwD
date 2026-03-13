const std = @import("std");
const scheduler_mod = @import("scheduler");
const parallel_scheduler_mod = @import("parallel_scheduler");
const stage_mod = @import("stage");
const parser_mod = @import("parser");

// Old/existing modules
const qc_mod = @import("qc");
const gc_mod = @import("gc");
const length_mod = @import("length");
const filter_mod = @import("filter");
const trim_mod = @import("trim");
const kmer_mod = @import("kmer");
const length_dist_mod = @import("length_dist");
const n50_mod = @import("n50");
const qual_decay_mod = @import("qual_decay");
const entropy_mod = @import("entropy");
const adapter_detect_mod = @import("adapter_detect");

// New FASTQ QC modules
const basic_stats_mod = @import("basic_stats");
const per_base_quality_mod = @import("per_base_quality");
const nucleotide_composition_mod = @import("nucleotide_composition");
const gc_content_mod = @import("gc_content");
const gc_distribution_mod = @import("gc_distribution");
const qc_length_dist_mod = @import("qc_length_dist"); // Avoid conflict
const n_statistics_mod = @import("n_statistics");
const qc_entropy_mod = @import("qc_entropy");
const kmer_spectrum_mod = @import("kmer_spectrum");
const overrepresented_mod = @import("overrepresented");
const duplication_mod = @import("duplication");
const qc_adapter_detect_mod = @import("qc_adapter_detect");

pub const Pipeline = struct {
    scheduler: ?scheduler_mod.Scheduler = null,
    parallel_scheduler: ?parallel_scheduler_mod.ParallelScheduler = null,
    arena: std.heap.ArenaAllocator,
    num_threads: usize,
    fast_mode: bool,

    pub fn init(child_allocator: std.mem.Allocator, num_threads: usize, fast_mode: bool) Pipeline {
        var pipe = Pipeline{
            .arena = std.heap.ArenaAllocator.init(child_allocator),
            .num_threads = num_threads,
            .fast_mode = fast_mode,
        };
        if (num_threads > 1) {
            pipe.parallel_scheduler = parallel_scheduler_mod.ParallelScheduler.init(child_allocator, num_threads);
        } else {
            pipe.scheduler = scheduler_mod.Scheduler.init(child_allocator);
        }
        return pipe;
    }

    pub fn deinit(self: *Pipeline) void {
        if (self.scheduler) |*s| s.deinit();
        if (self.parallel_scheduler) |*ps| ps.deinit();
        self.arena.deinit();
    }

    pub fn addStageByName(self: *Pipeline, name: []const u8) !void {
        const allocator = self.arena.allocator();
        var s_opt: ?stage_mod.Stage = null;

        if (std.mem.eql(u8, name, "qc")) {
            const s = try allocator.create(qc_mod.QcStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "gc")) {
            const s = try allocator.create(gc_mod.GcStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "length")) {
            const s = try allocator.create(length_mod.LengthStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "filter")) {
            const s = try allocator.create(filter_mod.FilterStage);
            s.* = filter_mod.FilterStage.init(20.0);
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "trim")) {
            const s = try allocator.create(trim_mod.TrimStage);
            s.* = trim_mod.TrimStage.init("AGCT");
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "kmer")) {
            const s = try allocator.create(kmer_mod.KmerStage);
            s.* = try kmer_mod.KmerStage.init(allocator, 5);
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "length_distribution")) {
            const s = try allocator.create(length_dist_mod.LengthDistributionStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "n50")) {
            const s = try allocator.create(n50_mod.N50Stage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "quality_decay")) {
            const s = try allocator.create(qual_decay_mod.QualityDecayStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "entropy")) {
            const s = try allocator.create(entropy_mod.EntropyStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "adapter_detect")) {
            const s = try allocator.create(adapter_detect_mod.AdapterDetectStage);
            s.* = try adapter_detect_mod.AdapterDetectStage.init(allocator);
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "basic_stats")) {
            const s = try allocator.create(basic_stats_mod.BasicStatsStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "per_base_quality")) {
            const s = try allocator.create(per_base_quality_mod.PerBaseQualityStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "nucleotide_composition")) {
            const s = try allocator.create(nucleotide_composition_mod.NucleotideCompositionStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "gc_content")) {
            const s = try allocator.create(gc_content_mod.GcContentStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "gc_distribution")) {
            const s = try allocator.create(gc_distribution_mod.GcDistributionStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "qc_length_dist")) {
            const s = try allocator.create(qc_length_dist_mod.LengthDistributionStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "n_statistics")) {
            const s = try allocator.create(n_statistics_mod.NStatisticsStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "qc_entropy")) {
            const s = try allocator.create(qc_entropy_mod.EntropyStage);
            s.* = .{};
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "kmer_spectrum")) {
            const s = try allocator.create(kmer_spectrum_mod.KmerSpectrumStage);
            s.* = try kmer_spectrum_mod.KmerSpectrumStage.init(allocator);
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "overrepresented")) {
            const s = try allocator.create(overrepresented_mod.OverrepresentedStage);
            s.* = overrepresented_mod.OverrepresentedStage.init(allocator, self.fast_mode);
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "duplication")) {
            const s = try allocator.create(duplication_mod.DuplicationStage);
            s.* = duplication_mod.DuplicationStage.init(allocator, self.fast_mode);
            s_opt = s.stage();
        } else if (std.mem.eql(u8, name, "qc_adapter_detect")) {
            const s = try allocator.create(qc_adapter_detect_mod.AdapterDetectionStage);
            s.* = try qc_adapter_detect_mod.AdapterDetectionStage.init(allocator);
            s_opt = s.stage();
        } else {
            return error.UnknownStage;
        }

        if (s_opt) |stage| {
            if (self.scheduler) |*s| {
                try s.registerStage(stage);
            } else if (self.parallel_scheduler) |*ps| {
                try ps.registerStage(stage);
            }
        }
    }

    pub fn run(self: *Pipeline, read: parser_mod.Read) !void {
        if (self.scheduler) |*s| {
            try s.process(read);
        } else if (self.parallel_scheduler) |*ps| {
            try ps.process(read);
        }
    }

    pub fn finalize(self: *Pipeline) !void {
        if (self.scheduler) |*s| {
            try s.finalize();
        } else if (self.parallel_scheduler) |*ps| {
            try ps.finalize();
        }
    }

    pub fn report(self: *Pipeline, writer: std.io.AnyWriter) void {
        if (self.scheduler) |*s| {
            s.report(writer);
        } else if (self.parallel_scheduler) |*ps| {
            ps.report(writer);
        }
    }
};
