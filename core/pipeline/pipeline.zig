const std = @import("std");
const scheduler_mod = @import("scheduler");
const stage_mod = @import("stage");
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
            s.* = filter_mod.FilterStage.init(20.0); // Default min_qual
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "trim")) {
            const s = try allocator.create(trim_mod.TrimStage);
            s.* = trim_mod.TrimStage.init("AGCT"); // Default adapter
            try self.scheduler.registerStage(s.stage());
        } else if (std.mem.eql(u8, name, "kmer")) {
            const s = try allocator.create(kmer_mod.KmerStage);
            s.* = try kmer_mod.KmerStage.init(allocator, 5); // Default k=5
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
        } else {
            return error.UnknownStage;
        }
    }

    pub fn run(self: *Pipeline, read: @import("parser").Read) !void {
        try self.scheduler.process(read);
    }

    pub fn finalize(self: *Pipeline) !void {
        try self.scheduler.finalize();
    }

    pub fn report(self: *Pipeline) void {
        self.scheduler.report();
    }
};
