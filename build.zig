const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Parsers and core structures
    const parser_mod = b.addModule("parser", .{
        .root_source_file = b.path("core/parser/parser.zig"),
    });
    
    const bam_reader_mod = b.addModule("bam_reader", .{
        .root_source_file = b.path("io/bam/bam_reader.zig"),
    });

    const cigar_parser_mod = b.addModule("cigar_parser", .{
        .root_source_file = b.path("core/cigar/cigar_parser.zig"),
    });

    // Stage interfaces
    const stage_interface_mod = b.addModule("stage", .{
        .root_source_file = b.path("core/stage/stage.zig"),
    });
    stage_interface_mod.addImport("parser", parser_mod);

    const bam_stage_interface_mod = b.addModule("bam_stage", .{
        .root_source_file = b.path("core/stage/bam_stage.zig"),
    });
    bam_stage_interface_mod.addImport("bam_reader", bam_reader_mod);

    // Schedulers
    const scheduler_mod = b.addModule("scheduler", .{
        .root_source_file = b.path("core/scheduler/scheduler.zig"),
    });
    scheduler_mod.addImport("parser", parser_mod);
    scheduler_mod.addImport("stage", stage_interface_mod);

    const bam_scheduler_mod = b.addModule("bam_scheduler", .{
        .root_source_file = b.path("core/scheduler/bam_scheduler.zig"),
    });
    bam_scheduler_mod.addImport("bam_reader", bam_reader_mod);
    bam_scheduler_mod.addImport("bam_stage", bam_stage_interface_mod);

    const allocator_mod = b.addModule("allocator", .{
        .root_source_file = b.path("core/allocator/allocator.zig"),
    });

    // Old Fastq Modules
    const qc_mod = b.addModule("qc", .{
        .root_source_file = b.path("stages/qc/qc_stage.zig"),
    });
    qc_mod.addImport("parser", parser_mod);
    qc_mod.addImport("stage", stage_interface_mod);

    const gc_mod = b.addModule("gc", .{
        .root_source_file = b.path("stages/gc/gc_stage.zig"),
    });
    gc_mod.addImport("parser", parser_mod);
    gc_mod.addImport("stage", stage_interface_mod);

    const length_mod = b.addModule("length", .{
        .root_source_file = b.path("stages/read_length/length_stage.zig"),
    });
    length_mod.addImport("parser", parser_mod);
    length_mod.addImport("stage", stage_interface_mod);

    const filter_mod = b.addModule("filter", .{
        .root_source_file = b.path("stages/filter/filter_stage.zig"),
    });
    filter_mod.addImport("parser", parser_mod);
    filter_mod.addImport("stage", stage_interface_mod);

    const trim_mod = b.addModule("trim", .{
        .root_source_file = b.path("stages/trim/trim_stage.zig"),
    });
    trim_mod.addImport("parser", parser_mod);
    trim_mod.addImport("stage", stage_interface_mod);

    const kmer_mod = b.addModule("kmer", .{
        .root_source_file = b.path("stages/kmer/kmer_stage.zig"),
    });
    kmer_mod.addImport("parser", parser_mod);
    kmer_mod.addImport("stage", stage_interface_mod);

    const length_dist_mod = b.addModule("length_dist", .{
        .root_source_file = b.path("stages/length_distribution/length_distribution_stage.zig"),
    });
    length_dist_mod.addImport("parser", parser_mod);
    length_dist_mod.addImport("stage", stage_interface_mod);

    const n50_mod = b.addModule("n50", .{
        .root_source_file = b.path("stages/n50/n50_stage.zig"),
    });
    n50_mod.addImport("parser", parser_mod);
    n50_mod.addImport("stage", stage_interface_mod);

    const qual_decay_mod = b.addModule("qual_decay", .{
        .root_source_file = b.path("stages/quality_decay/quality_decay_stage.zig"),
    });
    qual_decay_mod.addImport("parser", parser_mod);
    qual_decay_mod.addImport("stage", stage_interface_mod);

    const entropy_mod = b.addModule("entropy", .{
        .root_source_file = b.path("stages/entropy/entropy_stage.zig"),
    });
    entropy_mod.addImport("parser", parser_mod);
    entropy_mod.addImport("stage", stage_interface_mod);

    const adapter_detect_mod = b.addModule("adapter_detect", .{
        .root_source_file = b.path("stages/adapter_detect/adapter_detect_stage.zig"),
    });
    adapter_detect_mod.addImport("parser", parser_mod);
    adapter_detect_mod.addImport("stage", stage_interface_mod);

    // New Fastq Modules (Phase V)
    const basic_stats_mod = b.addModule("basic_stats", .{
        .root_source_file = b.path("stages/qc/basic_stats_stage.zig"),
    });
    basic_stats_mod.addImport("parser", parser_mod);
    basic_stats_mod.addImport("stage", stage_interface_mod);

    const per_base_quality_mod = b.addModule("per_base_quality", .{
        .root_source_file = b.path("stages/qc/per_base_quality_stage.zig"),
    });
    per_base_quality_mod.addImport("parser", parser_mod);
    per_base_quality_mod.addImport("stage", stage_interface_mod);

    const nucleotide_composition_mod = b.addModule("nucleotide_composition", .{
        .root_source_file = b.path("stages/qc/nucleotide_composition_stage.zig"),
    });
    nucleotide_composition_mod.addImport("parser", parser_mod);
    nucleotide_composition_mod.addImport("stage", stage_interface_mod);

    const gc_content_mod = b.addModule("gc_content", .{
        .root_source_file = b.path("stages/qc/gc_content_stage.zig"),
    });
    gc_content_mod.addImport("parser", parser_mod);
    gc_content_mod.addImport("stage", stage_interface_mod);

    const gc_distribution_mod = b.addModule("gc_distribution", .{
        .root_source_file = b.path("stages/qc/gc_distribution_stage.zig"),
    });
    gc_distribution_mod.addImport("parser", parser_mod);
    gc_distribution_mod.addImport("stage", stage_interface_mod);

    const qc_length_dist_mod = b.addModule("qc_length_dist", .{
        .root_source_file = b.path("stages/qc/length_distribution_stage.zig"),
    });
    qc_length_dist_mod.addImport("parser", parser_mod);
    qc_length_dist_mod.addImport("stage", stage_interface_mod);

    const n_statistics_mod = b.addModule("n_statistics", .{
        .root_source_file = b.path("stages/qc/n_statistics_stage.zig"),
    });
    n_statistics_mod.addImport("parser", parser_mod);
    n_statistics_mod.addImport("stage", stage_interface_mod);

    const qc_entropy_mod = b.addModule("qc_entropy", .{
        .root_source_file = b.path("stages/qc/entropy_stage.zig"),
    });
    qc_entropy_mod.addImport("parser", parser_mod);
    qc_entropy_mod.addImport("stage", stage_interface_mod);

    const kmer_spectrum_mod = b.addModule("kmer_spectrum", .{
        .root_source_file = b.path("stages/qc/kmer_spectrum_stage.zig"),
    });
    kmer_spectrum_mod.addImport("parser", parser_mod);
    kmer_spectrum_mod.addImport("stage", stage_interface_mod);

    const overrepresented_mod = b.addModule("overrepresented", .{
        .root_source_file = b.path("stages/qc/overrepresented_stage.zig"),
    });
    overrepresented_mod.addImport("parser", parser_mod);
    overrepresented_mod.addImport("stage", stage_interface_mod);

    const duplication_mod = b.addModule("duplication", .{
        .root_source_file = b.path("stages/qc/duplication_stage.zig"),
    });
    duplication_mod.addImport("parser", parser_mod);
    duplication_mod.addImport("stage", stage_interface_mod);

    const qc_adapter_detect_mod = b.addModule("qc_adapter_detect", .{
        .root_source_file = b.path("stages/qc/adapter_detection_stage.zig"),
    });
    qc_adapter_detect_mod.addImport("parser", parser_mod);
    qc_adapter_detect_mod.addImport("stage", stage_interface_mod);

    // BAM Analytics Modules
    const alignment_stats_mod = b.addModule("alignment_stats", .{
        .root_source_file = b.path("stages/alignment/alignment_stats_stage.zig"),
    });
    alignment_stats_mod.addImport("bam_reader", bam_reader_mod);
    alignment_stats_mod.addImport("bam_stage", bam_stage_interface_mod);

    const mapq_dist_mod = b.addModule("mapq_dist", .{
        .root_source_file = b.path("stages/alignment/mapq_distribution_stage.zig"),
    });
    mapq_dist_mod.addImport("bam_reader", bam_reader_mod);
    mapq_dist_mod.addImport("bam_stage", bam_stage_interface_mod);

    const insert_size_mod = b.addModule("insert_size", .{
        .root_source_file = b.path("stages/alignment/insert_size_stage.zig"),
    });
    insert_size_mod.addImport("bam_reader", bam_reader_mod);
    insert_size_mod.addImport("bam_stage", bam_stage_interface_mod);

    const coverage_mod = b.addModule("coverage", .{
        .root_source_file = b.path("stages/alignment/coverage_stage.zig"),
    });
    coverage_mod.addImport("bam_reader", bam_reader_mod);
    coverage_mod.addImport("bam_stage", bam_stage_interface_mod);
    coverage_mod.addImport("cigar_parser", cigar_parser_mod);

    const error_rate_mod = b.addModule("error_rate", .{
        .root_source_file = b.path("stages/alignment/error_rate_stage.zig"),
    });
    error_rate_mod.addImport("bam_reader", bam_reader_mod);
    error_rate_mod.addImport("bam_stage", bam_stage_interface_mod);
    error_rate_mod.addImport("cigar_parser", cigar_parser_mod);

    const soft_clip_mod = b.addModule("soft_clip", .{
        .root_source_file = b.path("stages/alignment/soft_clip_stage.zig"),
    });
    soft_clip_mod.addImport("bam_reader", bam_reader_mod);
    soft_clip_mod.addImport("bam_stage", bam_stage_interface_mod);
    soft_clip_mod.addImport("cigar_parser", cigar_parser_mod);

    const metrics_mod = b.addModule("metrics", .{
        .root_source_file = b.path("core/metrics/metrics.zig"),
    });
    metrics_mod.addImport("scheduler", scheduler_mod);

    const pipeline_mod = b.addModule("pipeline", .{
        .root_source_file = b.path("core/pipeline/pipeline.zig"),
    });
    pipeline_mod.addImport("scheduler", scheduler_mod);
    pipeline_mod.addImport("stage", stage_interface_mod);
    pipeline_mod.addImport("parser", parser_mod);
    pipeline_mod.addImport("qc", qc_mod);
    pipeline_mod.addImport("gc", gc_mod);
    pipeline_mod.addImport("length", length_mod);
    pipeline_mod.addImport("filter", filter_mod);
    pipeline_mod.addImport("trim", trim_mod);
    pipeline_mod.addImport("kmer", kmer_mod);
    pipeline_mod.addImport("length_dist", length_dist_mod);
    pipeline_mod.addImport("n50", n50_mod);
    pipeline_mod.addImport("qual_decay", qual_decay_mod);
    pipeline_mod.addImport("entropy", entropy_mod);
    pipeline_mod.addImport("adapter_detect", adapter_detect_mod);
    
    // Add all new fastq modules to pipeline
    pipeline_mod.addImport("basic_stats", basic_stats_mod);
    pipeline_mod.addImport("per_base_quality", per_base_quality_mod);
    pipeline_mod.addImport("nucleotide_composition", nucleotide_composition_mod);
    pipeline_mod.addImport("gc_content", gc_content_mod);
    pipeline_mod.addImport("gc_distribution", gc_distribution_mod);
    pipeline_mod.addImport("qc_length_dist", qc_length_dist_mod);
    pipeline_mod.addImport("n_statistics", n_statistics_mod);
    pipeline_mod.addImport("qc_entropy", qc_entropy_mod);
    pipeline_mod.addImport("kmer_spectrum", kmer_spectrum_mod);
    pipeline_mod.addImport("overrepresented", overrepresented_mod);
    pipeline_mod.addImport("duplication", duplication_mod);
    pipeline_mod.addImport("qc_adapter_detect", qc_adapter_detect_mod);

    const bam_pipeline_mod = b.addModule("bam_pipeline", .{
        .root_source_file = b.path("core/pipeline/bam_pipeline.zig"),
    });
    bam_pipeline_mod.addImport("bam_scheduler", bam_scheduler_mod);
    bam_pipeline_mod.addImport("bam_stage", bam_stage_interface_mod);
    bam_pipeline_mod.addImport("bam_reader", bam_reader_mod);
    bam_pipeline_mod.addImport("alignment_stats", alignment_stats_mod);
    bam_pipeline_mod.addImport("mapq_dist", mapq_dist_mod);
    bam_pipeline_mod.addImport("insert_size", insert_size_mod);
    bam_pipeline_mod.addImport("coverage", coverage_mod);
    bam_pipeline_mod.addImport("error_rate", error_rate_mod);
    bam_pipeline_mod.addImport("soft_clip", soft_clip_mod);

    // CLI Executable
    const exe = b.addExecutable(.{
        .name = "qwd",
        .root_source_file = b.path("apps/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("parser", parser_mod);
    exe.root_module.addImport("scheduler", scheduler_mod);
    exe.root_module.addImport("allocator", allocator_mod);
    exe.root_module.addImport("pipeline", pipeline_mod);
    exe.root_module.addImport("metrics", metrics_mod);
    exe.root_module.addImport("bam_reader", bam_reader_mod);
    exe.root_module.addImport("bam_pipeline", bam_pipeline_mod);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    // Tests
    const fastq_tests = b.addTest(.{
        .root_source_file = b.path("tests/fastq/fastq_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    fastq_tests.root_module.addImport("parser", parser_mod);
    fastq_tests.root_module.addImport("qc_entropy", qc_entropy_mod);
    fastq_tests.root_module.addImport("kmer_spectrum", kmer_spectrum_mod);
    fastq_tests.root_module.addImport("gc_distribution", gc_distribution_mod);
    fastq_tests.root_module.addImport("duplication", duplication_mod);
    fastq_tests.root_module.addImport("qc_adapter_detect", qc_adapter_detect_mod);
    const run_fastq_tests = b.addRunArtifact(fastq_tests);

    const bam_tests = b.addTest(.{
        .root_source_file = b.path("tests/bam/bam_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    bam_tests.root_module.addImport("bam_reader", bam_reader_mod);
    bam_tests.root_module.addImport("alignment_stats", alignment_stats_mod);
    bam_tests.root_module.addImport("mapq_dist", mapq_dist_mod);
    bam_tests.root_module.addImport("coverage", coverage_mod);
    bam_tests.root_module.addImport("error_rate", error_rate_mod);
    bam_tests.root_module.addImport("soft_clip", soft_clip_mod);
    const run_bam_tests = b.addRunArtifact(bam_tests);

    test_step.dependOn(&run_fastq_tests.step);
    test_step.dependOn(&run_bam_tests.step);
}
