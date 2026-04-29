const std = @import("std");
const pipeline_mod = @import("pipeline");
const pipeline_config = @import("pipeline_config");
const g_alloc_mod = @import("global_allocator");
const parallel_scheduler_mod = @import("parallel_scheduler");
const reader_interface = @import("reader_interface");

pub export fn main(argc: c_int, argv: [*:null]const ?[*:0]const u8) c_int {
    const allocator = std.heap.page_allocator;

    if (argc < 2) {
        std.debug.print("Usage: qwd <input.fastq>\n", .{});
        return 1;
    }

    const path = std.mem.span(argv[1].?);
    
    var g_alloc = g_alloc_mod.GlobalAllocator.init(allocator, 1500 * 1024 * 1024);
    const engine_allocator = g_alloc.allocator();

    var config = pipeline_config.PipelineConfig.default();
    config.threads = 8;
    
    var pipeline = pipeline_mod.Pipeline.init(engine_allocator, config);
    pipeline.addDefaultStages() catch |err| {
        std.debug.print("[CLI] Stages Error: {any}\n", .{err});
        return 1;
    };

    // High-Performance Parallel Path
    var io_threaded = std.Io.Threaded.init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();
    
    const file = std.Io.Dir.openFile(std.Io.Dir.cwd(), io, path, .{}) catch |err| {
        std.debug.print("[CLI] File Open Error: {any}\n", .{err});
        return 1;
    };
    defer file.close(io);
    
    const reader_ctx = reader_interface.Reader.IoReaderContext{ .file = file, .io = io };
    const reader = reader_interface.Reader.fromIoFile(&reader_ctx);

    var scheduler = parallel_scheduler_mod.ParallelScheduler.init(engine_allocator, config.threads, config.mode, .auto);
    
    pipeline.run(reader, scheduler.scheduler()) catch |err| {
        std.debug.print("[CLI] Run Error: {any}\n", .{err});
        return 1;
    };
    pipeline.finalize() catch |err| {
        std.debug.print("[CLI] Finalize Error: {any}\n", .{err});
        return 1;
    };

    std.debug.print("\nAnalysis Complete\n", .{});
    
    // Final stable bridge to stdout
    var stdout_buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    
    pipeline.reportJson(&writer.interface) catch |err| {
        std.debug.print("[CLI] JSON Error: {any}\n", .{err});
    };
    writer.interface.print("\n", .{}) catch {};
    writer.interface.flush() catch {};

    return 0;
}
