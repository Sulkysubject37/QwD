const std = @import("std");
const pipeline_mod = @import("pipeline");
const pipeline_config_mod = @import("pipeline_config");
const parser_mod = @import("parser");
const bam_pipeline_mod = @import("bam_pipeline");
const bam_reader_mod = @import("bam_reader");
const runtime_metrics = @import("runtime_metrics");
pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Default 1GB limit, can be overridden by --max-memory
    var max_memory: usize = 1024 * 1024 * 1024;

    // We need to parse --max-memory early to initialize the allocator
    var arg_iter = std.process.Args.Iterator.init(init.minimal.args);
    _ = arg_iter.next(); // skip exe
    while (arg_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--max-memory")) {
            if (arg_iter.next()) |val| {
                const mb = std.fmt.parseInt(usize, val, 10) catch 1024;
                max_memory = mb * 1024 * 1024;
            }
        }
    }

    var g_alloc = @import("global_allocator").GlobalAllocator.init(std.heap.c_allocator, max_memory);
    const allocator = g_alloc.allocator();

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
    } else if (std.mem.eql(u8, cmd, "investigate")) {
        const file_path = iter.next() orelse {
            std.debug.print("Error: Missing path for investigate\n", .{});
            return;
        };

        const file = try std.Io.Dir.openFile(.cwd(), io, file_path, .{});
        defer file.close(io);

        std.debug.print("[Investigate] Initializing FastqParser (sequential)...\n", .{});
        var p = try parser_mod.FastqParser.initWithFile(allocator, file, io, 256 * 1024);
        defer p.deinit();

        var count: usize = 0;
        var len1_count: usize = 0;
        var buf: [1024 * 1024]u8 = undefined;

        std.debug.print("[Investigate] Scanning {s}...\n", .{file_path});
        while (true) {
            const read = p.next(&buf) catch |err| {
                std.debug.print("Error during parsing at record {d}: {s}\n", .{count, @errorName(err)});
                break;
            };
            if (read == null) {
                std.debug.print("[Investigate] Parsing finished (returned null).\n", .{});
                break;
            }
            
            count += 1;
            if (read.?.seq.len == 1) {
                len1_count += 1;
                std.debug.print("Found length 1 record at index {d}\n", .{count});
            }
            if (count % 1000000 == 0) {
                std.debug.print("[Investigate] Processed {d}M records...\n", .{count / 1000000});
            }
        }

        std.debug.print("\n[Results]\n", .{});
        std.debug.print("Total records: {d}\n", .{count});
        std.debug.print("Records with length 1: {d}\n", .{len1_count});

        if (len1_count == 0) {
            std.debug.print("Conclusion: Sequential parser found 0 records of length 1. Parallel scheduler has a desync bug.\n", .{});
        } else {
            std.debug.print("Conclusion: Sequential parser found {d} records of length 1. The file itself is the source of the 'staining'.\n", .{len1_count});
        }
    }
}

fn printHelp() void {
    std.debug.print("QwD CLI v1.3.0 (Zig 0.16.0-dev)\n", .{});
    std.debug.print("Usage:\n", .{});
    std.debug.print("  qwd qc <file> [--threads <n>]\n", .{});
    std.debug.print("  qwd investigate <file>\n", .{});
}
