const std = @import("std");
const parser_mod = @import("parser");
const allocator_mod = @import("allocator");
const pipeline_mod = @import("pipeline");
const pipeline_config_mod = @import("pipeline_config");
const metrics_mod = @import("metrics");

const bam_reader_mod = @import("bam_reader");
const bam_pipeline_mod = @import("bam_pipeline");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var qwd_alloc = allocator_mod.createArena(allocator);
    defer allocator_mod.destroyArena(&qwd_alloc);
    const arena_allocator = qwd_alloc.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <qc|fastq-stats|pipeline|entropy|n50|quality-decay|adapter-detect|bamstats|run> [options] <file>\n", .{args[0]});
        return;
    }

    var num_threads: usize = 1;
    var command: []const u8 = undefined;
    var file_path: []const u8 = undefined;
    var stage_list_or_config: []const u8 = undefined;

    // A better argument parser
    var positional_args = std.ArrayList([]const u8).init(allocator);
    defer positional_args.deinit();

    var i: usize = 1;
    var force_scalar = false;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--threads")) {
            if (i + 1 < args.len) {
                num_threads = try std.fmt.parseInt(usize, args[i + 1], 10);
                i += 1;
                continue;
            }
        } else if (std.mem.eql(u8, args[i], "--no-simd")) {
            force_scalar = true;
            continue;
        } else if (std.mem.eql(u8, args[i], "--config")) {
            if (i + 1 < args.len) {
                stage_list_or_config = args[i + 1];
                i += 1;
                continue;
            }
        } else {
            try positional_args.append(args[i]);
        }
    }

    if (positional_args.items.len == 0) {
        std.debug.print("Missing command.\n", .{});
        return;
    }

    command = positional_args.items[0];
    
    // Apply global SIMD control
    @import("simd_ops").force_scalar = force_scalar;

    const stdout = std.io.getStdOut().writer().any();

    if (std.mem.eql(u8, command, "bamstats")) {
        if (positional_args.items.len < 2) return;
        file_path = positional_args.items[1];
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var buffered_reader = std.io.bufferedReader(file.reader());
        const reader = buffered_reader.reader().any();

        var bam_reader = try bam_reader_mod.BamReader.init(allocator, reader);
        defer bam_reader.deinit();

        var bam_pipeline = bam_pipeline_mod.BamPipeline.init(arena_allocator);
        defer bam_pipeline.deinit();
        try bam_pipeline.addDefaultStages();

        const record_buffer = try arena_allocator.alloc(u8, 65536);
        while (try bam_reader.next(record_buffer)) |record| {
            try bam_pipeline.run(record);
        }

        try bam_pipeline.finalize();
        try bam_pipeline.report(stdout);
        return;
    }

    var pipeline = pipeline_mod.Pipeline.init(arena_allocator, num_threads);
    defer pipeline.deinit();

    if (std.mem.eql(u8, command, "qc") or std.mem.eql(u8, command, "fastq-stats")) {
        if (positional_args.items.len < 2) return;
        file_path = positional_args.items[1];
        try pipeline.addStageByName("basic_stats");
        try pipeline.addStageByName("per_base_quality");
        try pipeline.addStageByName("nucleotide_composition");
        try pipeline.addStageByName("gc_content");
        try pipeline.addStageByName("gc_distribution");
        try pipeline.addStageByName("qc_length_dist");
        try pipeline.addStageByName("n_statistics");
        try pipeline.addStageByName("qc_entropy");
        try pipeline.addStageByName("kmer_spectrum");
        try pipeline.addStageByName("overrepresented");
        try pipeline.addStageByName("duplication");
        try pipeline.addStageByName("qc_adapter_detect");
    } else if (std.mem.eql(u8, command, "pipeline")) {
        if (positional_args.items.len < 3) {
            std.debug.print("Usage: {s} pipeline <stage1,stage2,...> <fastq_file>\n", .{args[0]});
            return;
        }
        const stage_list = positional_args.items[1];
        file_path = positional_args.items[2];

        var it = std.mem.split(u8, stage_list, ",");
        while (it.next()) |stage_name| {
            try pipeline.addStageByName(stage_name);
        }
    } else if (std.mem.eql(u8, command, "run")) {
        // e.g. qwd run --config pipeline.json reads.fastq
        if (positional_args.items.len < 2 or stage_list_or_config.len == 0) {
            std.debug.print("Usage: {s} run --config pipeline.json <fastq_file>\n", .{args[0]});
            return;
        }
        file_path = positional_args.items[1];

        const config_file = try std.fs.cwd().openFile(stage_list_or_config, .{});
        defer config_file.close();
        const json_data = try config_file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(json_data);

        const parsed = try pipeline_config_mod.PipelineConfig.parseJson(allocator, json_data);
        defer parsed.deinit();

        for (parsed.value.pipeline) |stage_name| {
            try pipeline.addStageByName(stage_name);
        }
    } else if (std.mem.eql(u8, command, "entropy")) {
        if (positional_args.items.len < 2) return;
        file_path = positional_args.items[1];
        try pipeline.addStageByName("qc_entropy");
    } else if (std.mem.eql(u8, command, "n50")) {
        if (positional_args.items.len < 2) return;
        file_path = positional_args.items[1];
        try pipeline.addStageByName("n_statistics");
    } else if (std.mem.eql(u8, command, "quality-decay")) {
        if (positional_args.items.len < 2) return;
        file_path = positional_args.items[1];
        try pipeline.addStageByName("per_base_quality");
    } else if (std.mem.eql(u8, command, "adapter-detect")) {
        if (positional_args.items.len < 2) return;
        file_path = positional_args.items[1];
        try pipeline.addStageByName("qc_adapter_detect");
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        return;
    }

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    const reader = buffered_reader.reader().any();

    var parser = try parser_mod.FastqParser.init(allocator, reader, 65536);
    defer parser.deinit();

    const record_buffer = try arena_allocator.alloc(u8, 65536);

    while (try parser.next(record_buffer)) |read| {
        try pipeline.run(read);
    }

    try pipeline.finalize();
    pipeline.report(stdout);
}
