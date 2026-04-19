const std = @import("std");
const pipeline_mod = @import("pipeline");
const pipeline_config_mod = @import("pipeline_config");
const parser_mod = @import("parser");
const bam_pipeline_mod = @import("bam_pipeline");
const bam_reader_mod = @import("bam_reader");
const runtime_metrics = @import("runtime_metrics");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Use thread-safe C allocator for high-performance multi-threading
    const allocator = std.heap.c_allocator;

    var iter = std.process.Args.Iterator.init(init.minimal.args);
    
    // Skip executable name
    _ = iter.next();

    const cmd = iter.next() orelse {
        printHelp();
        return;
    };

    if (std.mem.eql(u8, cmd, "qc")) {
        var file_path: ?[]const u8 = null;
        var threads: usize = 1;

        while (iter.next()) |arg| {
            if (std.mem.eql(u8, arg, "--threads")) {
                const thread_str = iter.next() orelse {
                    std.debug.print("Error: Missing value for --threads\n", .{});
                    return;
                };
                threads = std.fmt.parseInt(usize, thread_str, 10) catch {
                    std.debug.print("Error: Invalid value for --threads: {s}\n", .{thread_str});
                    return;
                };
            } else if (file_path == null) {
                file_path = arg;
            }
        }

        const path = file_path orelse {
            std.debug.print("Error: Missing path for qc\n", .{});
            return;
        };
        
        // Open file using the modern Io context
        const file = try std.Io.Dir.openFile(.cwd(), io, path, .{});
        defer file.close(io);
        
        var config = pipeline_config_mod.PipelineConfig.default();
        config.threads = threads;

        var pipeline = pipeline_mod.Pipeline.init(allocator, config);
        try pipeline.addDefaultStages();
        try pipeline.run(file, io);
        
        // Finalize before report
        try pipeline.finalize();
        
        // Final report using io
        const report = try pipeline.reportJsonAlloc(allocator, io);
        defer allocator.free(std.mem.span(report));
        
        var out_buf: [32768]u8 = undefined;
        var w = std.Io.File.stdout().writer(io, &out_buf);
        try w.interface.print("{s}\n", .{report});
        try w.interface.flush();
    }
}

fn printHelp() void {
    std.debug.print("QwD CLI v1.3.0 (Zig 0.16.0-dev)\n", .{});
    std.debug.print("Usage: qwd qc <file> [--threads <n>]\n", .{});
}
