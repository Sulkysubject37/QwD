const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 0. GLOBAL FLAGS
    const global_cflags = &[_][]const u8{ "-DIMGUI_DEFINE_MATH_OPERATORS", "-DSOKOL_METAL", "-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS", "-DIMGUI_DISABLE_OBSOLETE_KEYIO", "-fno-exceptions", "-fno-rtti" };

    // 1. CORE ENGINE MODULES
    const mode_mod = b.createModule(.{ .root_source_file = b.path("core/config/mode.zig"), .target = target, .optimize = optimize });
    const global_allocator_mod = b.createModule(.{ .root_source_file = b.path("core/memory/global_allocator.zig"), .target = target, .optimize = optimize });
    const simd_transpose_mod = b.createModule(.{ .root_source_file = b.path("core/simd/simd_transpose.zig"), .target = target, .optimize = optimize });
    const dna_2bit_mod = b.createModule(.{ .root_source_file = b.path("core/encoding/dna_2bit.zig"), .target = target, .optimize = optimize });
    const reader_mod = b.createModule(.{ .root_source_file = b.path("core/io/reader_interface.zig"), .target = target, .optimize = optimize });
    const common_mod = b.createModule(.{ .root_source_file = b.path("bindings/common.zig"), .target = target, .optimize = optimize });
    const blocking_sync_mod = b.createModule(.{ .root_source_file = b.path("core/parallel/blocking_sync.zig") });

    const fastq_block_mod = b.createModule(.{ .root_source_file = b.path("core/columnar/fastq_block.zig"), .target = target, .optimize = optimize });
    fastq_block_mod.addImport("simd_transpose", simd_transpose_mod);
    fastq_block_mod.addImport("dna_2bit", dna_2bit_mod);

    const bitplanes_mod = b.createModule(.{ .root_source_file = b.path("core/columnar/bitplane_core.zig"), .target = target, .optimize = optimize });
    const stage_mod = b.createModule(.{ .root_source_file = b.path("core/stage/stage.zig"), .target = target, .optimize = optimize });
    stage_mod.addImport("fastq_block", fastq_block_mod);
    stage_mod.addImport("bitplanes", bitplanes_mod);

    const telemetry_mod = b.createModule(.{ .root_source_file = b.path("core/api/telemetry_interface.zig"), .target = target, .optimize = optimize });
    telemetry_mod.addImport("fastq_block", fastq_block_mod);
    telemetry_mod.addImport("bitplanes", bitplanes_mod);

    const scheduler_mod = b.createModule(.{ .root_source_file = b.path("core/scheduler/scheduler_interface.zig"), .target = target, .optimize = optimize });
    scheduler_mod.addImport("reader_interface", reader_mod);
    scheduler_mod.addImport("stage", stage_mod);

    const deflate_impl_mod = b.createModule(.{ .root_source_file = b.path("core/io/deflate_fallback.zig"), .target = target, .optimize = optimize });
    deflate_impl_mod.addImport("custom_deflate.zig", b.createModule(.{ .root_source_file = b.path("core/io/custom_deflate.zig") }));

    const bgzf_mod = b.createModule(.{ .root_source_file = b.path("core/io/bgzf_native_reader.zig"), .target = target, .optimize = optimize });
    bgzf_mod.addImport("reader_interface", reader_mod);
    bgzf_mod.addImport("deflate_impl", deflate_impl_mod);

    const block_reader_mod = b.createModule(.{ .root_source_file = b.path("core/io/block_reader.zig"), .target = target, .optimize = optimize });
    block_reader_mod.addImport("bgzf_native_reader", bgzf_mod);
    block_reader_mod.addImport("reader_interface", reader_mod);

    const parser_mod = b.createModule(.{ .root_source_file = b.path("core/parser/parser.zig"), .target = target, .optimize = optimize });
    const pipeline_config_mod = b.createModule(.{ .root_source_file = b.path("core/config/pipeline_config.zig"), .target = target, .optimize = optimize });
    pipeline_config_mod.addImport("mode", mode_mod);
    parser_mod.addImport("mode", mode_mod);
    parser_mod.addImport("fastq_block", fastq_block_mod);
    parser_mod.addImport("bitplanes", bitplanes_mod);
    parser_mod.addImport("reader_interface", reader_mod);
    parser_mod.addImport("block_reader", block_reader_mod);

    // 2. STAGES
    const basic_stats_mod = b.createModule(.{ .root_source_file = b.path("stages/qc/basic_stats_stage.zig"), .target = target, .optimize = optimize });
    basic_stats_mod.addImport("fastq_block", fastq_block_mod);
    basic_stats_mod.addImport("bitplanes", bitplanes_mod);
    basic_stats_mod.addImport("stage", stage_mod);
    
    const gc_dist_mod = b.createModule(.{ .root_source_file = b.path("stages/qc/gc_distribution_stage.zig"), .target = target, .optimize = optimize });
    gc_dist_mod.addImport("fastq_block", fastq_block_mod);
    gc_dist_mod.addImport("bitplanes", bitplanes_mod);
    gc_dist_mod.addImport("stage", stage_mod);
    
    const n_stats_mod = b.createModule(.{ .root_source_file = b.path("stages/qc/n_statistics_stage.zig"), .target = target, .optimize = optimize });
    n_stats_mod.addImport("fastq_block", fastq_block_mod);
    n_stats_mod.addImport("bitplanes", bitplanes_mod);
    n_stats_mod.addImport("stage", stage_mod);
    
    const length_dist_mod = b.createModule(.{ .root_source_file = b.path("stages/qc/length_distribution_stage.zig"), .target = target, .optimize = optimize });
    length_dist_mod.addImport("fastq_block", fastq_block_mod);
    length_dist_mod.addImport("bitplanes", bitplanes_mod);
    length_dist_mod.addImport("stage", stage_mod);
    
    const quality_dist_mod = b.createModule(.{ .root_source_file = b.path("stages/qc/quality_dist_stage.zig"), .target = target, .optimize = optimize });
    quality_dist_mod.addImport("fastq_block", fastq_block_mod);
    quality_dist_mod.addImport("bitplanes", bitplanes_mod);
    quality_dist_mod.addImport("stage", stage_mod);
    
    const nucleotide_comp_mod = b.createModule(.{ .root_source_file = b.path("stages/qc/nucleotide_composition_stage.zig"), .target = target, .optimize = optimize });
    nucleotide_comp_mod.addImport("fastq_block", fastq_block_mod);
    nucleotide_comp_mod.addImport("bitplanes", bitplanes_mod);
    nucleotide_comp_mod.addImport("stage", stage_mod);

    const pipeline_mod = b.createModule(.{ .root_source_file = b.path("core/pipeline/pipeline.zig"), .target = target, .optimize = optimize });
    pipeline_mod.addImport("mode", mode_mod);
    pipeline_mod.addImport("pipeline_config", pipeline_config_mod);
    pipeline_mod.addImport("stage", stage_mod);
    pipeline_mod.addImport("parser", parser_mod);
    pipeline_mod.addImport("reader_interface", reader_mod);
    pipeline_mod.addImport("scheduler_interface", scheduler_mod);
    
    pipeline_mod.addImport("basic_stats", basic_stats_mod);
    pipeline_mod.addImport("gc_distribution", gc_dist_mod);
    pipeline_mod.addImport("n_statistics", n_stats_mod);
    pipeline_mod.addImport("length_distribution", length_dist_mod);
    pipeline_mod.addImport("quality_dist", quality_dist_mod);
    pipeline_mod.addImport("nucleotide_composition", nucleotide_comp_mod);
    
    // Remaining dummies
    pipeline_mod.addImport("adapter_detection", basic_stats_mod);
    pipeline_mod.addImport("duplication", basic_stats_mod);
    pipeline_mod.addImport("entropy", basic_stats_mod);
    pipeline_mod.addImport("kmer_spectrum", basic_stats_mod);
    pipeline_mod.addImport("overrepresented", basic_stats_mod);
    pipeline_mod.addImport("per_base_quality", basic_stats_mod);
    pipeline_mod.addImport("taxed", basic_stats_mod);

    const sync_scheduler_mod = b.createModule(.{ .root_source_file = b.path("core/scheduler/synchronous_scheduler.zig"), .target = target, .optimize = optimize });
    sync_scheduler_mod.addImport("reader_interface", reader_mod);
    sync_scheduler_mod.addImport("stage", stage_mod);
    sync_scheduler_mod.addImport("scheduler_interface", scheduler_mod);
    sync_scheduler_mod.addImport("parser", parser_mod);
    sync_scheduler_mod.addImport("mode", mode_mod);
    sync_scheduler_mod.addImport("fastq_block", fastq_block_mod);
    sync_scheduler_mod.addImport("bitplanes", bitplanes_mod);

    const parallel_scheduler_mod = b.createModule(.{ .root_source_file = b.path("core/parallel/parallel_scheduler.zig"), .target = target, .optimize = optimize });
    parallel_scheduler_mod.addImport("mode", mode_mod);
    parallel_scheduler_mod.addImport("fastq_block", fastq_block_mod);
    parallel_scheduler_mod.addImport("bitplanes", bitplanes_mod);
    parallel_scheduler_mod.addImport("global_allocator", global_allocator_mod);
    parallel_scheduler_mod.addImport("parser", parser_mod);
    parallel_scheduler_mod.addImport("stage", stage_mod);
    parallel_scheduler_mod.addImport("reader_interface", reader_mod);
    parallel_scheduler_mod.addImport("scheduler_interface", scheduler_mod);
    parallel_scheduler_mod.addImport("simd_transpose", simd_transpose_mod);
    parallel_scheduler_mod.addImport("telemetry", telemetry_mod);
    parallel_scheduler_mod.addImport("bgzf_native_reader", bgzf_mod);
    parallel_scheduler_mod.addImport("deflate_impl", deflate_impl_mod);
    
    const ring_buffer_mod = b.createModule(.{ .root_source_file = b.path("core/parallel/ring_buffer.zig") });
    ring_buffer_mod.addImport("blocking_sync", blocking_sync_mod);
    const ordered_slots_mod = b.createModule(.{ .root_source_file = b.path("core/parallel/ordered_slots.zig") });
    ordered_slots_mod.addImport("blocking_sync", blocking_sync_mod);
    const proxy_reader_mod = b.createModule(.{ .root_source_file = b.path("core/io/proxy_reader.zig") });
    proxy_reader_mod.addImport("reader_interface", reader_mod);
    proxy_reader_mod.addImport("ordered_slots", ordered_slots_mod);
    
    parallel_scheduler_mod.addImport("ring_buffer", ring_buffer_mod);
    parallel_scheduler_mod.addImport("ordered_slots", ordered_slots_mod);
    parallel_scheduler_mod.addImport("proxy_reader", proxy_reader_mod);
    parallel_scheduler_mod.addImport("raw_batch", b.createModule(.{ .root_source_file = b.path("core/batch/raw_batch.zig") }));

    // 3. THE KERNEL (Native Bridge)
    const native_bridge_mod = b.createModule(.{ .root_source_file = b.path("bindings/c/qwd_native.zig"), .target = target, .optimize = optimize, .link_libc = true });
    native_bridge_mod.addImport("pipeline", pipeline_mod);
    native_bridge_mod.addImport("pipeline_config", pipeline_config_mod);
    native_bridge_mod.addImport("global_allocator", global_allocator_mod);
    native_bridge_mod.addImport("reader_interface", reader_mod);
    native_bridge_mod.addImport("synchronous_scheduler", sync_scheduler_mod);
    native_bridge_mod.addImport("parallel_scheduler", parallel_scheduler_mod);
    native_bridge_mod.addImport("common", common_mod);
    native_bridge_mod.addImport("telemetry", telemetry_mod);
    native_bridge_mod.addImport("bitplanes", bitplanes_mod);
    native_bridge_mod.addImport("fastq_block", fastq_block_mod);

    const kernel = b.addLibrary(.{ .name = "qwd_core", .root_module = native_bridge_mod, .linkage = .static });
    kernel.root_module.linkSystemLibrary("deflate", .{});
    kernel.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    kernel.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });

    // 4. THE WORKSTATION
    const dep_sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize });
    const dep_imgui = b.dependency("imgui", .{ .target = target, .optimize = optimize });
    const workstation_dummy_root = b.addObject(.{ .name = "workstation_dummy", .root_module = b.createModule(.{ .root_source_file = b.path("apps/dashboard/main.zig"), .target = target, .optimize = optimize, .link_libc = true }) });

    const exe = b.addExecutable(.{ .name = "qwd-workstation", .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .link_libcpp = true }) });
    exe.root_module.addObject(workstation_dummy_root);
    exe.root_module.linkLibrary(kernel);
    exe.root_module.addIncludePath(b.path("bindings/c"));
    exe.root_module.addIncludePath(dep_imgui.path(""));
    exe.root_module.addIncludePath(dep_sokol.path("src/sokol/c"));
    exe.root_module.addCSourceFile(.{ .file = b.path("apps/dashboard/imgui_monolith.mm"), .flags = global_cflags });
    exe.root_module.addCSourceFile(.{ .file = b.path("apps/dashboard/imgui_impl.cpp"), .flags = global_cflags });
    exe.root_module.addCSourceFile(.{ .file = dep_imgui.path("imgui.cpp"), .flags = global_cflags });
    exe.root_module.addCSourceFile(.{ .file = dep_imgui.path("imgui_draw.cpp"), .flags = global_cflags });
    exe.root_module.addCSourceFile(.{ .file = dep_imgui.path("imgui_widgets.cpp"), .flags = global_cflags });
    exe.root_module.addCSourceFile(.{ .file = dep_imgui.path("imgui_tables.cpp"), .flags = global_cflags });
    exe.root_module.addCSourceFile(.{ .file = dep_imgui.path("imgui_demo.cpp"), .flags = global_cflags });

    if (target.result.os.tag == .macos) {
        exe.root_module.linkFramework("Metal", .{});
        exe.root_module.linkFramework("AppKit", .{});
        exe.root_module.linkFramework("QuartzCore", .{});
        exe.root_module.linkFramework("AudioToolbox", .{});
        exe.root_module.linkSystemLibrary("deflate", .{});
    }
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run-workstation", "Run the Native Workstation");
    run_step.dependOn(&run_cmd.step);

    // 5. CLI
    const cli_root = b.createModule(.{ .root_source_file = b.path("apps/cli/main.zig"), .target = target, .optimize = optimize, .link_libc = true });
    cli_root.addImport("pipeline", pipeline_mod);
    cli_root.addImport("pipeline_config", pipeline_config_mod);
    cli_root.addImport("global_allocator", global_allocator_mod);
    cli_root.addImport("parallel_scheduler", parallel_scheduler_mod);
    cli_root.addImport("reader_interface", reader_mod);
    const cli = b.addExecutable(.{ .name = "qwd", .root_module = cli_root });
    cli.root_module.linkSystemLibrary("deflate", .{});
    cli.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    cli.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    b.installArtifact(cli);
}
