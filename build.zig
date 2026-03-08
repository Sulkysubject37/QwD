const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    const parser_mod = b.addModule("parser", .{
        .root_source_file = b.path("core/parser/parser.zig"),
    });
    const stage_interface_mod = b.addModule("stage", .{
        .root_source_file = b.path("core/stage/stage.zig"),
    });
    stage_interface_mod.addImport("parser", parser_mod);

    const scheduler_mod = b.addModule("scheduler", .{
        .root_source_file = b.path("core/scheduler/scheduler.zig"),
    });
    scheduler_mod.addImport("parser", parser_mod);
    scheduler_mod.addImport("stage", stage_interface_mod);

    const allocator_mod = b.addModule("allocator", .{
        .root_source_file = b.path("core/allocator/allocator.zig"),
    });

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

    const metrics_mod = b.addModule("metrics", .{
        .root_source_file = b.path("core/metrics/metrics.zig"),
    });
    metrics_mod.addImport("scheduler", scheduler_mod);

    const pipeline_mod = b.addModule("pipeline", .{
        .root_source_file = b.path("core/pipeline/pipeline.zig"),
    });
    pipeline_mod.addImport("scheduler", scheduler_mod);
    pipeline_mod.addImport("stage", stage_interface_mod);
    pipeline_mod.addImport("qc", qc_mod);
    pipeline_mod.addImport("gc", gc_mod);
    pipeline_mod.addImport("length", length_mod);
    pipeline_mod.addImport("filter", filter_mod);
    pipeline_mod.addImport("trim", trim_mod);
    pipeline_mod.addImport("kmer", kmer_mod);
    pipeline_mod.addImport("parser", parser_mod);

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
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    // Core Tests
    const parser_tests = b.addTest(.{
        .root_source_file = b.path("core/parser/parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);

    const scheduler_tests = b.addTest(.{
        .root_source_file = b.path("core/scheduler/scheduler.zig"),
        .target = target,
        .optimize = optimize,
    });
    scheduler_tests.root_module.addImport("parser", parser_mod);
    scheduler_tests.root_module.addImport("stage", stage_interface_mod);
    const run_scheduler_tests = b.addRunArtifact(scheduler_tests);

    const allocator_tests = b.addTest(.{
        .root_source_file = b.path("core/allocator/allocator.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_allocator_tests = b.addRunArtifact(allocator_tests);

    const stage_tests = b.addTest(.{
        .root_source_file = b.path("tests/stages/stage_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    stage_tests.root_module.addImport("parser", parser_mod);
    stage_tests.root_module.addImport("qc", qc_mod);
    stage_tests.root_module.addImport("gc", gc_mod);
    stage_tests.root_module.addImport("length", length_mod);
    const run_stage_tests = b.addRunArtifact(stage_tests);

    const kmer_tests = b.addTest(.{
        .root_source_file = b.path("tests/stages/kmer_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    kmer_tests.root_module.addImport("parser", parser_mod);
    kmer_tests.root_module.addImport("kmer", kmer_mod);
    const run_kmer_tests = b.addRunArtifact(kmer_tests);

    const pipeline_tests = b.addTest(.{
        .root_source_file = b.path("tests/pipeline/pipeline_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    pipeline_tests.root_module.addImport("parser", parser_mod);
    pipeline_tests.root_module.addImport("pipeline", pipeline_mod);
    const run_pipeline_tests = b.addRunArtifact(pipeline_tests);

    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_scheduler_tests.step);
    test_step.dependOn(&run_allocator_tests.step);
    test_step.dependOn(&run_stage_tests.step);
    test_step.dependOn(&run_kmer_tests.step);
    test_step.dependOn(&run_pipeline_tests.step);
}
