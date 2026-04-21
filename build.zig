const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const with_libdeflate = b.option(bool, "with-libdeflate", "Build with libdeflate") orelse (target.result.os.tag != .windows);
    const options = b.addOptions();
    options.addOption(bool, "HAVE_LIBDEFLATE", with_libdeflate);

    // --- Core Modules ---
    const mode_mod = b.addModule("mode", .{ .root_source_file = b.path("core/config/mode.zig") });
    const ring_buffer_mod = b.addModule("ring_buffer", .{ .root_source_file = b.path("core/parallel/ring_buffer.zig") });
    const entropy_lut_mod = b.addModule("entropy_lut", .{ .root_source_file = b.path("core/entropy/entropy_lut.zig") });
    const structured_output_mod = b.addModule("structured_output", .{ .root_source_file = b.path("core/output/structured_output.zig") });
    const pipeline_config_mod = b.addModule("pipeline_config", .{ .root_source_file = b.path("core/config/pipeline_config.zig") });
    pipeline_config_mod.addImport("mode", mode_mod);
    const global_allocator_mod = b.addModule("global_allocator", .{ .root_source_file = b.path("core/memory/global_allocator.zig") });
    const runtime_metrics_mod = b.addModule("runtime_metrics", .{ .root_source_file = b.path("core/metrics/runtime_metrics.zig") });

    // SIMD & Transposition
    const simd_ops_mod = b.addModule("simd_ops", .{ .root_source_file = b.path("core/simd/simd_ops.zig") });
    const column_ops_mod = b.addModule("column_ops", .{ .root_source_file = b.path("core/vector/column_ops.zig") });
    const simd_transpose_mod = b.addModule("simd_transpose", .{ .root_source_file = b.path("core/simd/simd_transpose.zig") });
    const vertical_scanner_mod = b.addModule("vertical_scanner", .{ .root_source_file = b.path("core/simd/vertical_scanner.zig") });
    const newline_scan_mod = b.addModule("newline_scan", .{ .root_source_file = b.path("core/simd/newline_scan.zig") });

    // Analytics Extras
    const bloom_filter_mod = b.addModule("bloom_filter", .{ .root_source_file = b.path("core/analytics/bloom_filter.zig") });
    const dna_2bit_mod = b.addModule("dna_2bit", .{ .root_source_file = b.path("core/encoding/dna_2bit.zig") });
    const cigar_parser_mod = b.addModule("cigar_parser", .{ .root_source_file = b.path("core/cigar/cigar_parser.zig") });
    const kmer_bitroll_mod = b.addModule("kmer_bitroll", .{ .root_source_file = b.path("core/simd/kmer_bitroll.zig") });
    const kmer_columnar_mod = b.addModule("kmer_columnar", .{ .root_source_file = b.path("core/vector/kmer_columnar.zig") });
    const kmer_counter_mod = b.addModule("kmer_counter", .{ .root_source_file = b.path("core/analytics/kmer_counter.zig") });

    // GZIP Native Engine
    const bit_sieve_mod = b.addModule("bit_sieve", .{ .root_source_file = b.path("core/io/bit_sieve.zig") });
    const huffman_mod = b.addModule("huffman", .{ .root_source_file = b.path("core/io/huffman_decoder.zig") });
    huffman_mod.addImport("bit_sieve", bit_sieve_mod);
    const lz77_mod = b.addModule("lz77", .{ .root_source_file = b.path("core/io/lz77_engine.zig") });
    const custom_deflate_mod = b.addModule("custom_deflate", .{ .root_source_file = b.path("core/io/custom_deflate.zig") });
    custom_deflate_mod.addImport("bit_sieve", bit_sieve_mod);
    custom_deflate_mod.addImport("huffman", huffman_mod);
    custom_deflate_mod.addImport("lz77", lz77_mod);
    
    const deflate_impl_path = if (with_libdeflate and target.result.os.tag == .macos) 
        "core/io/deflate_libdeflate.zig" 
    else 
        "core/io/deflate_fallback.zig";
    
    const deflate_impl_mod = b.addModule("deflate_impl", .{ .root_source_file = b.path(deflate_impl_path) });
    const deflate_wrapper_mod = b.addModule("deflate_wrapper", .{ .root_source_file = b.path("core/io/deflate_wrapper.zig") });
    deflate_wrapper_mod.addImport("deflate_impl", deflate_impl_mod);
    deflate_wrapper_mod.addImport("custom_deflate", custom_deflate_mod);
    deflate_wrapper_mod.addOptions("build_options", options);
    
    if (with_libdeflate and target.result.os.tag == .macos) {
        deflate_impl_mod.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    }
    
    const bgzf_native_reader_mod = b.addModule("bgzf_native_reader", .{ .root_source_file = b.path("core/io/bgzf_native_reader.zig") });
    const gzip_reader_mod = b.addModule("gzip_reader", .{ .root_source_file = b.path("core/io/gzip_reader.zig") });
    gzip_reader_mod.addImport("mode", mode_mod);
    gzip_reader_mod.addImport("ring_buffer", ring_buffer_mod);
    gzip_reader_mod.addImport("deflate_wrapper", deflate_wrapper_mod);
    gzip_reader_mod.addImport("custom_deflate", custom_deflate_mod);

    // Parsing
    const block_reader_mod = b.addModule("block_reader", .{ .root_source_file = b.path("core/io/block_reader.zig") });
    block_reader_mod.addImport("mode", mode_mod);
    block_reader_mod.addImport("gzip_reader", gzip_reader_mod);
    block_reader_mod.addImport("bgzf_native_reader", bgzf_native_reader_mod);
    block_reader_mod.addImport("deflate_impl", deflate_impl_mod);
    const parser_mod = b.addModule("parser", .{ .root_source_file = b.path("core/parser/parser.zig") });
    parser_mod.addImport("block_reader", block_reader_mod);
    parser_mod.addImport("newline_scan", newline_scan_mod);
    parser_mod.addImport("mode", mode_mod);
    
    const chunk_builder_mod = b.addModule("chunk_builder", .{ .root_source_file = b.path("core/batch/chunk_builder.zig") });
    chunk_builder_mod.addImport("parser", parser_mod);
    chunk_builder_mod.addImport("block_reader", block_reader_mod);
    
    const bgzf_chunk_builder_mod = b.addModule("bgzf_chunk_builder", .{ .root_source_file = b.path("core/batch/bgzf_chunk_builder.zig") });
    bgzf_chunk_builder_mod.addImport("bgzf_native_reader", bgzf_native_reader_mod);

    // Columnar
    const bitplanes_mod = b.addModule("bitplanes", .{ .root_source_file = b.path("core/columnar/bitplane_core.zig") });
    bitplanes_mod.addImport("dna_2bit", dna_2bit_mod);
    const fastq_block_mod = b.addModule("fastq_block", .{ .root_source_file = b.path("core/columnar/fastq_block.zig") });
    fastq_block_mod.addImport("simd_transpose", simd_transpose_mod);
    const stage_interface_mod = b.addModule("stage", .{ .root_source_file = b.path("core/stage/stage.zig") });
    stage_interface_mod.addImport("parser", parser_mod);
    stage_interface_mod.addImport("fastq_block", fastq_block_mod);
    stage_interface_mod.addImport("bitplanes", bitplanes_mod);

    // --- Artifact Root Modules ---
    const cli_root = b.createModule(.{
        .root_source_file = b.path("apps/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const api_root = b.createModule(.{
        .root_source_file = b.path("bindings/c/qwd_api.zig"),
        .target = target,
        .optimize = optimize,
    });

    // QC Stages
    const qc_list = [_]struct { n: []const u8, p: []const u8 }{
        .{ .n = "qc", .p = "stages/qc/qc_stage.zig" },
        .{ .n = "gc", .p = "stages/gc/gc_stage.zig" },
        .{ .n = "basic_stats", .p = "stages/qc/basic_stats_stage.zig" },
        .{ .n = "per_base_quality", .p = "stages/qc/per_base_quality_stage.zig" },
        .{ .n = "nucleotide_composition", .p = "stages/qc/nucleotide_composition_stage.zig" },
        .{ .n = "gc_distribution", .p = "stages/qc/gc_distribution_stage.zig" },
        .{ .n = "qc_length_dist", .p = "stages/qc/length_distribution_stage.zig" },
        .{ .n = "n_statistics", .p = "stages/qc/n_statistics_stage.zig" },
        .{ .n = "qc_entropy", .p = "stages/qc/entropy_stage.zig" },
        .{ .n = "kmer_spectrum", .p = "stages/qc/kmer_spectrum_stage.zig" },
        .{ .n = "overrepresented", .p = "stages/qc/overrepresented_stage.zig" },
        .{ .n = "duplication", .p = "stages/qc/duplication_stage.zig" },
        .{ .n = "qc_adapter_detect", .p = "stages/qc/adapter_detection_stage.zig" },
        .{ .n = "trim", .p = "stages/trim/trim_stage.zig" },
        .{ .n = "filter", .p = "stages/filter/filter_stage.zig" },
        .{ .n = "kmer", .p = "stages/kmer/kmer_stage.zig" },
        .{ .n = "quality_dist", .p = "stages/qc/quality_dist_stage.zig" },
        .{ .n = "taxed", .p = "stages/qc/taxed_stage.zig" },
    };

    var stage_mods = std.StringHashMap(*std.Build.Module).init(b.allocator);
    for (qc_list) |s| {
        const mod = b.addModule(s.n, .{ .root_source_file = b.path(s.p) });
        mod.addImport("stage", stage_interface_mod);
        mod.addImport("parser", parser_mod);
        mod.addImport("fastq_block", fastq_block_mod);
        mod.addImport("bitplanes", bitplanes_mod);
        mod.addImport("mode", mode_mod);
        mod.addImport("simd_ops", simd_ops_mod);
        mod.addImport("column_ops", column_ops_mod);
        mod.addImport("structured_output", structured_output_mod);
        if (std.mem.eql(u8, s.n, "qc_entropy")) mod.addImport("entropy_lut", entropy_lut_mod);
        if (std.mem.eql(u8, s.n, "duplication")) mod.addImport("bloom_filter", bloom_filter_mod);
        if (std.mem.eql(u8, s.n, "taxed")) {
            mod.addImport("kmer_bitroll", kmer_bitroll_mod);
            mod.addImport("kmer_columnar", kmer_columnar_mod);
            mod.addImport("dna_2bit", dna_2bit_mod);
        }
        if (std.mem.eql(u8, s.n, "kmer_spectrum")) {
            mod.addImport("kmer_bitroll", kmer_bitroll_mod);
            mod.addImport("kmer_columnar", kmer_columnar_mod);
            mod.addImport("dna_2bit", dna_2bit_mod);
            mod.addImport("kmer_counter", kmer_counter_mod);
        }
        if (std.mem.eql(u8, s.n, "kmer")) mod.addImport("kmer_columnar", kmer_columnar_mod);
        stage_mods.put(s.n, mod) catch unreachable;
    }

    // BAM Stack
    const bam_reader_mod = b.addModule("bam_reader", .{ .root_source_file = b.path("io/bam/bam_reader.zig") });
    const bam_stage_mod = b.addModule("bam_stage", .{ .root_source_file = b.path("core/stage/bam_stage.zig") });
    bam_stage_mod.addImport("bam_reader", bam_reader_mod);
    const bam_scheduler_mod = b.addModule("bam_scheduler", .{ .root_source_file = b.path("core/scheduler/bam_scheduler.zig") });
    bam_scheduler_mod.addImport("bam_reader", bam_reader_mod);
    bam_scheduler_mod.addImport("bam_stage", bam_stage_mod);

    const bam_stages = [_]struct { n: []const u8, p: []const u8 }{
        .{ .n = "alignment_stats", .p = "stages/alignment/alignment_stats_stage.zig" },
        .{ .n = "mapq_dist", .p = "stages/alignment/mapq_distribution_stage.zig" },
        .{ .n = "insert_size", .p = "stages/alignment/insert_size_stage.zig" },
        .{ .n = "coverage", .p = "stages/alignment/coverage_stage.zig" },
        .{ .n = "error_rate", .p = "stages/alignment/error_rate_stage.zig" },
        .{ .n = "soft_clip", .p = "stages/alignment/soft_clip_stage.zig" },
    };

    var bam_stage_mods = std.StringHashMap(*std.Build.Module).init(b.allocator);
    for (bam_stages) |s| {
        const mod = b.addModule(s.n, .{ .root_source_file = b.path(s.p) });
        mod.addImport("bam_reader", bam_reader_mod);
        mod.addImport("bam_stage", bam_stage_mod);
        mod.addImport("cigar_parser", cigar_parser_mod);
        bam_stage_mods.put(s.n, mod) catch unreachable;
    }

    const bam_pipeline_mod = b.addModule("bam_pipeline", .{ .root_source_file = b.path("core/pipeline/bam_pipeline.zig") });
    bam_pipeline_mod.addImport("bam_reader", bam_reader_mod);
    bam_pipeline_mod.addImport("bam_scheduler", bam_scheduler_mod);
    bam_pipeline_mod.addImport("bam_stage", bam_stage_mod);
    bam_pipeline_mod.addImport("structured_output", structured_output_mod);
    var bit = bam_stage_mods.iterator();
    while (bit.next()) |e| {
        bam_pipeline_mod.addImport(e.key_ptr.*, e.value_ptr.*);
        cli_root.addImport(e.key_ptr.*, e.value_ptr.*);
        api_root.addImport(e.key_ptr.*, e.value_ptr.*);
    }

    // Pipeline & Schedulers
    const scheduler_mod = b.addModule("scheduler", .{ .root_source_file = b.path("core/scheduler/scheduler.zig") });
    scheduler_mod.addImport("parser", parser_mod);
    scheduler_mod.addImport("stage", stage_interface_mod);

    const parallel_scheduler_mod = b.addModule("parallel_scheduler", .{ .root_source_file = b.path("core/parallel/parallel_scheduler.zig") });
    parallel_scheduler_mod.addImport("parser", parser_mod);
    parallel_scheduler_mod.addImport("stage", stage_interface_mod);
    parallel_scheduler_mod.addImport("ring_buffer", ring_buffer_mod);
    parallel_scheduler_mod.addImport("block_reader", block_reader_mod);
    parallel_scheduler_mod.addImport("mode", mode_mod);
    parallel_scheduler_mod.addImport("custom_deflate", custom_deflate_mod);
    parallel_scheduler_mod.addImport("deflate_wrapper", deflate_wrapper_mod);
    parallel_scheduler_mod.addImport("fastq_block", fastq_block_mod);
    parallel_scheduler_mod.addImport("bitplanes", bitplanes_mod);
    parallel_scheduler_mod.addImport("vertical_scanner", vertical_scanner_mod);
    parallel_scheduler_mod.addImport("bgzf_native_reader", bgzf_native_reader_mod);
    parallel_scheduler_mod.addImport("deflate_impl", deflate_impl_mod);
    parallel_scheduler_mod.addImport("global_allocator", global_allocator_mod);

    const pipeline_mod = b.addModule("pipeline", .{ .root_source_file = b.path("core/pipeline/pipeline.zig") });
    pipeline_mod.addImport("parallel_scheduler", parallel_scheduler_mod);
    pipeline_mod.addImport("scheduler", scheduler_mod);
    pipeline_mod.addImport("block_reader", block_reader_mod);
    pipeline_mod.addImport("parser", parser_mod);
    pipeline_mod.addImport("mode", mode_mod);
    pipeline_mod.addImport("pipeline_config", pipeline_config_mod);
    pipeline_mod.addImport("stage", stage_interface_mod);
    pipeline_mod.addImport("bgzf_native_reader", bgzf_native_reader_mod);
    pipeline_mod.addImport("bgzf_chunk_builder", bgzf_chunk_builder_mod);
    pipeline_mod.addImport("bloom_filter", bloom_filter_mod);
    pipeline_mod.addImport("structured_output", structured_output_mod);
    var it = stage_mods.iterator();
    while (it.next()) |e| {
        pipeline_mod.addImport(e.key_ptr.*, e.value_ptr.*);
        cli_root.addImport(e.key_ptr.*, e.value_ptr.*);
        api_root.addImport(e.key_ptr.*, e.value_ptr.*);
    }

    // --- Artifact Root Modules ---
    cli_root.addImport("pipeline", pipeline_mod);
    cli_root.addImport("parser", parser_mod);
    cli_root.addImport("mode", mode_mod);
    cli_root.addImport("entropy_lut", entropy_lut_mod);
    cli_root.addImport("bam_pipeline", bam_pipeline_mod);
    cli_root.addImport("bam_reader", bam_reader_mod);
    cli_root.addImport("structured_output", structured_output_mod);
    cli_root.addImport("pipeline_config", pipeline_config_mod);
    cli_root.addImport("global_allocator", global_allocator_mod);
    cli_root.addImport("runtime_metrics", runtime_metrics_mod);
    cli_root.addImport("chunk_builder", chunk_builder_mod);
    cli_root.addImport("bgzf_chunk_builder", bgzf_chunk_builder_mod);
    cli_root.addImport("bgzf_native_reader", bgzf_native_reader_mod);
    cli_root.addOptions("build_options", options);

    api_root.addImport("pipeline", pipeline_mod);
    api_root.addImport("parser", parser_mod);
    api_root.addImport("mode", mode_mod);
    api_root.addImport("entropy_lut", entropy_lut_mod);
    api_root.addImport("bam_pipeline", bam_pipeline_mod);
    api_root.addImport("bam_reader", bam_reader_mod);
    api_root.addImport("structured_output", structured_output_mod);
    api_root.addImport("pipeline_config", pipeline_config_mod);
    api_root.addImport("global_allocator", global_allocator_mod);
    api_root.addImport("runtime_metrics", runtime_metrics_mod);
    api_root.addImport("chunk_builder", chunk_builder_mod);
    api_root.addImport("bgzf_chunk_builder", bgzf_chunk_builder_mod);
    api_root.addImport("bgzf_native_reader", bgzf_native_reader_mod);
    api_root.addOptions("build_options", options);

    // --- Artifacts ---
    const qwd_exe = b.addExecutable(.{ .name = "qwd", .root_module = cli_root });
    const qwd_lib_shared = b.addLibrary(.{ .name = "qwd", .root_module = api_root, .linkage = .dynamic });
    const qwd_lib_static = b.addLibrary(.{ .name = "qwd", .root_module = api_root, .linkage = .static });

    const arts = [_]*std.Build.Step.Compile{ qwd_exe, qwd_lib_shared, qwd_lib_static };

    for (arts) |art| {
        // Mobile Compatibility: Only link libdeflate if not targeting iOS
        const is_ios = target.result.os.tag == .ios;
        if (with_libdeflate and !is_ios) {
            art.root_module.linkSystemLibrary("deflate", .{});
            if (target.result.os.tag == .macos) {
                art.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
                art.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
            }
        }
        art.root_module.link_libc = true;
        art.bundle_compiler_rt = true;
        b.installArtifact(art);
    }

    const test_step = b.step("test", "Run unit tests");
    const io_tests = [_][]const u8{ "tests/io/test_bit_sieve.zig", "tests/io/test_deflate_wrapper.zig" };
    for (io_tests) |p| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(p),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("bit_sieve", bit_sieve_mod);
        test_mod.addImport("deflate_wrapper", deflate_wrapper_mod);
        test_mod.addOptions("build_options", options);

        const t = b.addTest(.{ .root_module = test_mod });
        
        if (with_libdeflate) {
            t.root_module.linkSystemLibrary("deflate", .{});
            if (target.result.os.tag == .macos) {
                t.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
                t.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
            }
        }
        t.root_module.link_libc = true;
        
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
