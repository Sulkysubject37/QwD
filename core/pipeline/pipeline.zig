const std = @import("std");
const scheduler_mod = @import("scheduler");
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
    scheduler: scheduler_mod.Scheduler,
    arena: std.heap.ArenaAllocator,

    pub fn init(child_allocator: std.mem.Allocator) Pipeline {
        return Pipeline{
            .scheduler = scheduler_mod.Scheduler.init(child_allocator),
            .arena = std.heap.ArenaAllocator.init(child_allocator),
        };
    }

    pub fn deinit(self: *Pipeline) void {
        self.scheduler.deinit();
        self.arena.deinit();
    }

    pub fn addStageByName(self: *Pipeline, name: []const u8) !void {
        const allocator = self.arena.allocator();
        
        // Backward compatibility
        if (std.mem.eql(u8, name, "qc")) {
            const s = try allocator.create(qc_mod.QcStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "gc")) {
            const s = try allocator.create(gc_mod.GcStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "length")) {
            const s = try allocator.create(length_mod.LengthStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "filter")) {
            const s = try allocator.create(filter_mod.FilterStage);
            s.* = filter_mod.FilterStage.init(20.0);
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "trim")) {
            const s = try allocator.create(trim_mod.TrimStage);
            s.* = trim_mod.TrimStage.init("AGCT");
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "kmer")) {
            const s = try allocator.create(kmer_mod.KmerStage);
            s.* = try kmer_mod.KmerStage.init(allocator, 5);
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "length_distribution")) {
            const s = try allocator.create(length_dist_mod.LengthDistributionStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "n50")) {
            const s = try allocator.create(n50_mod.N50Stage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "quality_decay")) {
            const s = try allocator.create(qual_decay_mod.QualityDecayStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "entropy")) {
            const s = try allocator.create(entropy_mod.EntropyStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "adapter_detect")) {
            const s = try allocator.create(adapter_detect_mod.AdapterDetectStage);
            s.* = try adapter_detect_mod.AdapterDetectStage.init(allocator);
            try self.scheduler.registerStage(s.stage());
            
        // New Phase V FASTQ QC stages
        } else if (std.mem.eql(u8, name, "basic_stats")) {
            const s = try allocator.create(basic_stats_mod.BasicStatsStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "per_base_quality")) {
            const s = try allocator.create(per_base_quality_mod.PerBaseQualityStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "nucleotide_composition")) {
            const s = try allocator.create(nucleotide_composition_mod.NucleotideCompositionStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "gc_content")) {
            const s = try allocator.create(gc_content_mod.GcContentStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "gc_distribution")) {
            const s = try allocator.create(gc_distribution_mod.GcDistributionStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "qc_length_dist")) {
            const s = try allocator.create(qc_length_dist_mod.LengthDistributionStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "n_statistics")) {
            const s = try allocator.create(n_statistics_mod.NStatisticsStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "qc_entropy")) {
            const s = try allocator.create(qc_entropy_mod.EntropyStage);
            s.* = .{};
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "kmer_spectrum")) {
            const s = try allocator.create(kmer_spectrum_mod.KmerSpectrumStage);
            s.* = try kmer_spectrum_mod.KmerSpectrumStage.init(allocator);
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "overrepresented")) {
            const s = try allocator.create(overrepresented_mod.OverrepresentedStage);
            s.* = overrepresented_mod.OverrepresentedStage.init(allocator);
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "duplication")) {
            const s = try allocator.create(duplication_mod.DuplicationStage);
            s.* = duplication_mod.DuplicationStage.init(allocator);
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "qc_adapter_detect")) {
            const s = try allocator.create(qc_adapter_detect_mod.AdapterDetectionStage);
            s.* = try qc_adapter_detect_mod.AdapterDetectionStage.init(allocator);
            try self.scheduler.registerStage(s.stage());
        } else {
            return error.UnknownStage;
        }
    }

    pub fn run(self: *Pipeline, read: parser_mod.Read) !void {
        try self.scheduler.process(read);
    }

    pub fn finalize(self: *Pipeline) !void {
        try self.scheduler.finalize();
    }

    pub fn report(self: *Pipeline) void {
        self.scheduler.report();
    }
};
