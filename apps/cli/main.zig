const std = @import("std");
const parser_mod = @import("parser");
const allocator_mod = @import("allocator");
const pipeline_mod = @import("pipeline");
const pipeline_config_mod = @import("pipeline_config");
const metrics_mod = @import("metrics");
const structured_output = @import("structured_output");
const runtime_metrics = @import("runtime_metrics");
const mode_mod = @import("mode");

const bam_reader_mod = @import("bam_reader");
const bam_pipeline_mod = @import("bam_pipeline");

pub fn main() !void {
    // Initialize global LUT for entropy
    @import("entropy_lut").initGlobal();
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2 or std.mem.eql(u8, args[1], "help") or std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        std.debug.print(
            \\QwD — high-performance streaming bioinformatics engine
            \\
            \\Usage: qwd <command> [options] <file>
            \\
            \\Subcommands:
            \\  qc              Run full Quality Control suite (FASTQ)
            \\  bamstats        Alignment and coverage analytics (BAM)
            \\  pipeline        Run custom pipeline from JSON config
            \\  entropy         Analyze sequence complexity (FASTQ)
            \\  n50             Calculate N-statistics (FASTQ)
            \\  quality-decay   Analyze quality drop-off (FASTQ)
            \\  adapter-detect  Detect common adapters (FASTQ)
            \\  help            Print this help message
            \\
            \\Options:
            \\  --threads N     Number of parallel threads (default: CPU count)
            \\  --mode <type>   Execution mode: 'exact' (deterministic) or 'fast' (probabilistic)
            \\  --fast          Shorthand for --mode fast
            \\  --json          Output results in structured JSON format
            \\  --ndjson        Output results in streaming NDJSON format
            \\  --max-memory N  Hard memory limit in MB (default: 1024)
            \\  --perf          Print detailed performance metrics
            \\
            \\Documentation: https://github.com/Sulkysubject37/QwD/blob/main/docs/cli_usage.md
            \\
        , .{});
        return;
    }

    const command = args[1];
    var num_threads: usize = std.Thread.getCpuCount() catch 1;
    var mode: mode_mod.Mode = .EXACT;
    var perf_mode = false;
    var mem_mb: usize = 16;
    var max_memory_mb: usize = 1024;
    var output_format: structured_output.OutputFormat = .text;

    var positional_args = std.ArrayList([]const u8).init(allocator);
    defer positional_args.deinit();

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--threads")) {
            i += 1;
            if (i < args.len) {
                num_threads = try std.fmt.parseInt(usize, args[i], 10);
            }
        } else if (std.mem.eql(u8, args[i], "--fast")) {
            mode = .FAST;
        } else if (std.mem.eql(u8, args[i], "--mode")) {
            i += 1;
            if (i < args.len) {
                if (std.mem.eql(u8, args[i], "fast")) {
                    mode = .FAST;
                } else if (std.mem.eql(u8, args[i], "exact")) {
                    mode = .EXACT;
                }
            }
        } else if (std.mem.eql(u8, args[i], "--perf")) {
            perf_mode = true;
        } else if (std.mem.eql(u8, args[i], "--memory")) {
            i += 1;
            if (i < args.len) mem_mb = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--max-memory")) {
            i += 1;
            if (i < args.len) max_memory_mb = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--json")) {
            output_format = .json;
        } else if (std.mem.eql(u8, args[i], "--ndjson")) {
            output_format = .ndjson;
        } else {
            try positional_args.append(args[i]);
        }
    }

    const stdout = std.io.getStdOut().writer().any();

    const global_allocator = @import("global_allocator");
    var global_pool = global_allocator.GlobalAllocator.init(allocator, max_memory_mb * 1024 * 1024);
    const pool_allocator = global_pool.allocator();

    const arena_allocator = pool_allocator;

    if (std.mem.eql(u8, command, "bamstats")) {
        if (positional_args.items.len < 1) return;
        const file_path = positional_args.items[0];
        
        var bam_pipeline = bam_pipeline_mod.BamPipeline.init(arena_allocator);
        defer bam_pipeline.deinit();

        try bam_pipeline.addDefaultStages();

        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        var bam_reader = try bam_reader_mod.BamReader.init(allocator, file.reader().any());
        defer bam_reader.deinit();

        var perf = runtime_metrics.RuntimeMetrics.start();
        
        var record_buf: [1024]u8 = undefined;
        while (try bam_reader.next(&record_buf)) |record| {
            try bam_pipeline.run(record);
        }

        try bam_pipeline.finalize();

        if (output_format == .json) {
            try structured_output.writeJsonReport(bam_pipeline.scheduler, stdout);
            try stdout.writeAll("\n");
        } else {
            try bam_pipeline.report(stdout);
            if (perf_mode) {
                perf.report(stdout);
            }
        }
        return;
    }

    var pipeline = pipeline_mod.Pipeline.init(arena_allocator, null);
    pipeline.mode = mode;
    defer pipeline.deinit();

    var file_path: []const u8 = "";

    if (std.mem.eql(u8, command, "qc") or std.mem.eql(u8, command, "fastq-stats")) {
        if (positional_args.items.len < 1) return;
        file_path = positional_args.items[0];
        try pipeline.addStage("basic-stats");
        try pipeline.addStage("per-base-quality");
        try pipeline.addStage("nucleotide-composition");
        try pipeline.addStage("gc-distribution");
        try pipeline.addStage("length-distribution");
        try pipeline.addStage("n-statistics");
        try pipeline.addStage("entropy");
        try pipeline.addStage("kmer-spectrum");
        try pipeline.addStage("overrepresented");
        try pipeline.addStage("duplication");
        try pipeline.addStage("adapter-detect");
    } else if (std.mem.eql(u8, command, "entropy")) {
        if (positional_args.items.len < 1) return;
        file_path = positional_args.items[0];
        try pipeline.addStage("entropy");
    } else if (std.mem.eql(u8, command, "n50")) {
        if (positional_args.items.len < 1) return;
        file_path = positional_args.items[0];
        try pipeline.addStage("n-statistics");
    } else if (std.mem.eql(u8, command, "quality-decay")) {
        if (positional_args.items.len < 1) return;
        file_path = positional_args.items[0];
        try pipeline.addStage("per-base-quality");
    } else if (std.mem.eql(u8, command, "adapter-detect")) {
        if (positional_args.items.len < 1) return;
        file_path = positional_args.items[0];
        try pipeline.addStage("adapter-detect");
    } else if (std.mem.eql(u8, command, "pipeline")) {
        if (positional_args.items.len < 2) return;
        const config_path = positional_args.items[0];
        file_path = positional_args.items[1];
        const config_data = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
        defer allocator.free(config_data);
        const parsed = try pipeline_config_mod.PipelineConfig.parseJson(allocator, config_data);
        defer parsed.deinit();
        for (parsed.value.pipeline) |stage_name| {
            try pipeline.addStage(stage_name);
        }
    } else if (std.mem.eql(u8, command, "run")) {
        if (positional_args.items.len < 1) return;
        file_path = positional_args.items[0];
        try pipeline.addStage("basic-stats");
        try pipeline.addStage("qc");
    }

    try pipeline.setupSchedulers(num_threads);

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var parser = if (mode == .FAST) blk: {
        break :blk try parser_mod.FastqParser.initMmap(arena_allocator, file);
    } else try parser_mod.FastqParser.init(allocator, file.reader().any(), (256 * 1024) + (1024 * 1024));
    defer parser.deinit();

    // Hyperscale Direct Chunked flow
    const chunk_builder_mod = @import("chunk_builder");
    var chunk_builder = chunk_builder_mod.ChunkBuilder.init(&parser, 256 * 1024);

    var perf = runtime_metrics.RuntimeMetrics.start();

    try pipeline.run_chunked(&chunk_builder);

    try pipeline.finalize();

    switch (output_format) {
        .json => {
            try structured_output.writeJsonReport(pipeline.parallel_scheduler.?, stdout);
            try stdout.writeAll("\n");
        },
        .ndjson => {
            const count = pipeline.parallel_scheduler.?.read_count.load(.monotonic);
            try structured_output.writeNdjsonProcess(count, stdout);
        },
        .text => {
            try stdout.print("\n--- QwD Execution Mode: {s} ---\n", .{@tagName(mode)});
            pipeline.report(stdout);
            if (perf_mode) {
                perf.report(stdout);
            }
        },
    }
}
