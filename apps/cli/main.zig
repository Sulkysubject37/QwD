const std = @import("std");
const parser_mod = @import("parser");
const allocator_mod = @import("allocator");
const pipeline_mod = @import("pipeline");
const pipeline_config_mod = @import("pipeline_config");
const metrics_mod = @import("metrics");
const structured_output = @import("structured_output");
const runtime_metrics = @import("runtime_metrics");
const mode_mod = @import("mode");
const bgzf_native_reader = @import("bgzf_native_reader");
const bgzf_chunk_builder = @import("bgzf_chunk_builder");
const chunk_builder_mod = @import("chunk_builder");

const bam_reader_mod = @import("bam_reader");
const bam_pipeline_mod = @import("bam_pipeline");

fn printHelp() void {
    std.debug.print(
        \\QwD — high-performance streaming bioinformatics engine (v1.1.0-stable)
        \\
        \\Usage: qwd <command> [options] <file>
        \\
        \\Subcommands:
        \\  qc              Run full Quality Control suite (FASTQ)
        \\  bamstats        Alignment and coverage analytics (BAM)
        \\  pipeline        Run custom pipeline from JSON config
        \\  entropy         Analyze sequence complexity (FASTQ)
        \\  n50             Calculate N-statistics (FASTQ)
        \\  adapter-detect  Detect common adapters (FASTQ)
        \\  version         Print version information
        \\  help            Print this help message
        \\
        \\Options:
        \\  --threads N      Number of parallel threads (default: CPU count)
        \\  --mode <type>    Execution mode: 'exact' (deterministic) or 'approx' (probabilistic)
        \\  --fast           Alias for '--mode approx'
        \\  --gzip-backend <m>  Backends: 'auto', 'native', 'libdeflate', 'compat'
        \\                   - auto: Detect BGZF and use parallel decompression if possible.
        \\                   - native: Force use of QwD native Zig decompression.
        \\                   - libdeflate: Force use of SIMD-accelerated libdeflate.
        \\                   - compat: Robust sequential decompression for standard GZ.
        \\  --json           Output results in structured JSON format
        \\  --max-memory N   Hard memory limit in MB (default: 1024)
        \\  --perf           Print detailed performance metrics
        \\  --quiet          Minimize output verbosity
        \\
        \\Documentation: https://github.com/Sulkysubject37/QwD/blob/main/docs/cli_usage.md
        \\
    , .{});
}

pub fn main() !void {
    @import("entropy_lut").initGlobal();
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
        std.debug.print("QwD v1.1.0-stable\n", .{});
        return;
    }
    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printHelp();
        return;
    }

    var num_threads: usize = std.Thread.getCpuCount() catch 1;
    var mode: mode_mod.Mode = .EXACT;
    var gzip_mode: mode_mod.GzipMode = .AUTO;
    var perf_mode = false;
    var quiet_mode = false;
    var max_memory_mb: usize = 1024;
    var output_format: structured_output.OutputFormat = .text;

    var positional_args = std.ArrayList([]const u8).init(allocator);
    defer positional_args.deinit();

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--threads")) {
            i += 1;
            if (i < args.len) num_threads = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--mode")) {
            i += 1;
            if (i < args.len) {
                if (std.mem.eql(u8, args[i], "approx") or std.mem.eql(u8, args[i], "fast")) {
                    mode = .APPROX;
                } else if (std.mem.eql(u8, args[i], "exact")) {
                    mode = .EXACT;
                }
            }
        } else if (std.mem.eql(u8, args[i], "--gzip-backend") or std.mem.eql(u8, args[i], "--gzip-mode")) {
            i += 1;
            if (i < args.len) {
                if (std.mem.eql(u8, args[i], "native") or std.mem.eql(u8, args[i], "qwd")) {
                    gzip_mode = .NATIVE;
                } else if (std.mem.eql(u8, args[i], "libdeflate")) {
                    gzip_mode = .LIBDEFLATE;
                } else if (std.mem.eql(u8, args[i], "chunked")) {
                    gzip_mode = .CHUNKED;
                } else if (std.mem.eql(u8, args[i], "compat")) {
                    gzip_mode = .COMPAT;
                } else {
                    gzip_mode = .AUTO;
                }
            }
        } else if (std.mem.eql(u8, args[i], "--fast")) {
            mode = .APPROX;
        } else if (std.mem.eql(u8, args[i], "--perf")) {
            perf_mode = true;
        } else if (std.mem.eql(u8, args[i], "--quiet")) {
            quiet_mode = true;
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

    const std_out_file = std.io.getStdOut();
    var bw = std.io.bufferedWriter(std_out_file.writer());
    const stdout = bw.writer().any();

    const global_allocator = @import("global_allocator");
    var global_pool = global_allocator.GlobalAllocator.init(allocator, max_memory_mb * 1024 * 1024);
    const pool_allocator = global_pool.allocator();

    if (std.mem.eql(u8, command, "bamstats")) {
        if (positional_args.items.len < 1) return;
        const file_path = positional_args.items[0];
        var bam_pipeline = bam_pipeline_mod.BamPipeline.init(pool_allocator);
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
        try bam_pipeline.report(stdout);
        if (perf_mode) perf.report(stdout);
        try bw.flush();
        return;
    }

    var pipeline = pipeline_mod.Pipeline.init(pool_allocator, null);
    pipeline.mode = mode;
    pipeline.gzip_mode = gzip_mode;
    defer pipeline.deinit();

    if (positional_args.items.len < 1) return;
    const file_path = positional_args.items[0];

    if (std.mem.eql(u8, command, "qc")) {
        try pipeline.addStage("basic_stats");
        try pipeline.addStage("per_base_quality");
        try pipeline.addStage("nucleotide_composition");
        try pipeline.addStage("gc_distribution");
        try pipeline.addStage("length_distribution");
        try pipeline.addStage("n_statistics");
        try pipeline.addStage("entropy");
        try pipeline.addStage("kmer_spectrum");
        try pipeline.addStage("overrepresented");
        try pipeline.addStage("duplication");
        try pipeline.addStage("adapter_detect");
    } else if (std.mem.eql(u8, command, "entropy")) {
        try pipeline.addStage("entropy");
    } else if (std.mem.eql(u8, command, "n50")) {
        try pipeline.addStage("n_statistics");
    } else if (std.mem.eql(u8, command, "quality-decay")) {
        try pipeline.addStage("per_base_quality");
    } else if (std.mem.eql(u8, command, "adapter-detect")) {
        try pipeline.addStage("adapter_detect");
    } else if (std.mem.eql(u8, command, "pipeline")) {
        const config_path = file_path;
        const config_data = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
        defer allocator.free(config_data);
        const parsed = try pipeline_config_mod.PipelineConfig.parseJson(allocator, config_data);
        defer parsed.deinit();
        for (parsed.value.pipeline) |stage_name| try pipeline.addStage(stage_name);
    }

    try pipeline.setupSchedulers(num_threads);

    const target_input = if (std.mem.eql(u8, command, "pipeline")) positional_args.items[1] else file_path;
    const file = try std.fs.cwd().openFile(target_input, .{});
    defer file.close();

    var fr = file.reader();
    const is_gz = std.mem.endsWith(u8, target_input, ".gz");
    
    var perf = runtime_metrics.RuntimeMetrics.start();

    if (num_threads > 1) {
        var is_actually_bgzf = false;
        if (is_gz) {
            // PROBE for BGZF
            try file.seekTo(0);
            is_actually_bgzf = bgzf_native_reader.BgzfNativeReader.isBgzf(file.reader());
            try file.seekTo(0); // Reset for the actual run
        }

        if (is_actually_bgzf and (gzip_mode == .NATIVE or gzip_mode == .AUTO)) {
            // HIGH-PERFORMANCE PATH: Parallel Decompression (BGZF only)
            var native_reader = try bgzf_native_reader.BgzfNativeReader.init(pool_allocator, file.reader().any());
            defer native_reader.deinit();
            var chunk_builder = bgzf_chunk_builder.BgzfChunkBuilder.init(pool_allocator, &native_reader);
            try pipeline.run_chunked(&chunk_builder);
        } else {
            // ROBUST PATH: Sequential Parsing (Standard GZ / Plain), Parallel Processing
            var parser = if (is_gz) 
                try parser_mod.FastqParser.initGzip(pool_allocator, file.reader().any(), 1024 * 1024, gzip_mode)
            else if (mode == .APPROX) 
                try parser_mod.FastqParser.initMmap(pool_allocator, file) 
            else 
                try parser_mod.FastqParser.init(pool_allocator, file.reader().any(), 1024 * 1024);
            defer parser.deinit();
            
            if (pipeline.parallel_scheduler) |*ps| {
                try ps.run_parallel(&parser, &pipeline);
            }
        }
    } else {
        var parser = if (is_gz) 
            try parser_mod.FastqParser.initGzip(pool_allocator, fr.any(), 1024 * 1024, gzip_mode) 
        else 
            try parser_mod.FastqParser.init(pool_allocator, fr.any(), 1024 * 1024);
        defer parser.deinit();
        
        const record_buffer = try pool_allocator.alloc(u8, 1024 * 1024);
        while (try parser.next(record_buffer)) |read| {
            pipeline.read_count += 1;
            for (pipeline.stages.items) |stage| {
                _ = try stage.process(&read);
            }
        }
        try pipeline.finalize();
    }

    if (output_format == .json) {
        try structured_output.writeJsonReport(&pipeline, stdout);
    } else {
        if (!quiet_mode) {
            try stdout.print("\n--- QwD Execution Mode: {s} ---\n", .{@tagName(mode)});
            pipeline.report(stdout);
            if (perf_mode) perf.report(stdout);
        }
    }
    try bw.flush();
}
