const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    const parser_mod = b.addModule("parser", .{
        .root_source_file = b.path("core/parser/parser.zig"),
    });
    const scheduler_mod = b.addModule("scheduler", .{
        .root_source_file = b.path("core/scheduler/scheduler.zig"),
    });
    scheduler_mod.addImport("parser", parser_mod);
    const allocator_mod = b.addModule("allocator", .{
        .root_source_file = b.path("core/allocator/allocator.zig"),
    });

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
    const run_scheduler_tests = b.addRunArtifact(scheduler_tests);

    const allocator_tests = b.addTest(.{
        .root_source_file = b.path("core/allocator/allocator.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_allocator_tests = b.addRunArtifact(allocator_tests);

    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_scheduler_tests.step);
    test_step.dependOn(&run_allocator_tests.step);
}
