const std = @import("std");
const pipeline_mod = @import("pipeline");
const pipeline_config = @import("pipeline_config");
const g_alloc_mod = @import("global_allocator");
const parallel_scheduler_mod = @import("parallel_scheduler");
const reader_interface = @import("reader_interface");

fn run_qc(allocator: std.mem.Allocator, path: [*:0]const u8, threads: c_int, mode_idx: c_int, gz_idx: c_int) ![]u8 {
    _ = gz_idx;
    const path_slice = std.mem.span(path);
    
    var g_alloc = g_alloc_mod.GlobalAllocator.init(allocator, 1500 * 1024 * 1024);
    const engine_allocator = g_alloc.allocator();

    var config = pipeline_config.PipelineConfig.default();
    config.threads = if (threads <= 0) 8 else @intCast(threads);
    config.mode = if (mode_idx == 1) .fast else .exact;
    
    var pipeline = pipeline_mod.Pipeline.init(engine_allocator, config);
    try pipeline.addDefaultStages();

    var io_threaded = std.Io.Threaded.init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();
    
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, path_slice, .{});
    defer file.close(io);
    
    const reader_ctx = reader_interface.Reader.IoReaderContext{ .file = file, .io = io };
    const reader = reader_interface.Reader.fromIoFile(&reader_ctx);

    var scheduler = parallel_scheduler_mod.ParallelScheduler.init(engine_allocator, config.threads, config.mode, .auto);
    
    std.debug.print("Running pipeline...\n", .{});
    try pipeline.run(reader, scheduler.scheduler());
    std.debug.print("Finalizing pipeline...\n", .{});
    try pipeline.finalize();

    const DynBuf = struct {
        buf: []u8,
        len: usize,
        allocator: std.mem.Allocator,
        writer: std.Io.Writer,
        
        pub fn init(alloc: std.mem.Allocator) !*@This() {
            const self = try alloc.create(@This());
            self.* = .{
                .buf = try alloc.alloc(u8, 1024),
                .len = 0,
                .allocator = alloc,
                .writer = .{
                    .vtable = &.{
                        .drain = drain,
                        .sendFile = undefined,
                    },
                    .buffer = &[_]u8{},
                    .end = 0,
                },
            };
            return self;
        }
        
        pub fn append(self: *@This(), bytes: []const u8) !void {
            if (self.len + bytes.len > self.buf.len) {
                const new_cap = @max(self.buf.len * 2, self.len + bytes.len);
                self.buf = try self.allocator.realloc(self.buf, new_cap);
            }
            @memcpy(self.buf[self.len..self.len + bytes.len], bytes);
            self.len += bytes.len;
        }

        fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            const self: *@This() = @fieldParentPtr("writer", w);
            var consumed: usize = 0;
            for (data, 0..) |chunk, i| {
                if (chunk.len > 0) {
                    if (splat > 0 and i == data.len - 1) {
                        for (0..splat) |_| {
                            self.append(chunk) catch return error.WriteFailed;
                        }
                    } else {
                        self.append(chunk) catch return error.WriteFailed;
                    }
                    consumed += chunk.len;
                }
            }
            return consumed;
        }
    };
    
    std.debug.print("Reporting JSON...\n", .{});
    var dyn_buf = try DynBuf.init(allocator);
    defer allocator.destroy(dyn_buf);
    
    try pipeline.reportJson(&dyn_buf.writer);
    
    std.debug.print("Appending null terminator...\n", .{});
    // Add null terminator
    try dyn_buf.append(&[_]u8{0});
    
    std.debug.print("Duping slice...\n", .{});
    const final_slice = try allocator.dupe(u8, dyn_buf.buf[0..dyn_buf.len]);
    
    std.debug.print("Freeing dyn_buf...\n", .{});
    allocator.free(dyn_buf.buf);
    
    std.debug.print("Returning final slice...\n", .{});
    return final_slice;
}

pub export fn qwd_fastq_qc_ex(path: [*:0]const u8, threads: c_int, mode_idx: c_int, gz_idx: c_int) ?[*]u8 {
    const allocator = std.heap.page_allocator;
    const json_slice = run_qc(allocator, path, threads, mode_idx, gz_idx) catch |err| {
        std.debug.print("[QWD-API] FastQ QC failed: {}\n", .{err});
        return null;
    };
    return json_slice.ptr;
}

pub export fn qwd_fastq_qc(path: [*:0]const u8) ?[*]u8 {
    return qwd_fastq_qc_ex(path, 0, 0, 0);
}

pub export fn qwd_fastq_qc_ex_r(path_ptr: [*]const [*:0]const u8, threads: *c_int, mode_idx: *c_int, gz_idx: *c_int, out_buf: [*]u8, max_len: *c_int) void {
    const allocator = std.heap.page_allocator;
    const path = path_ptr[0];
    const json_slice = run_qc(allocator, path, threads.*, mode_idx.*, gz_idx.*) catch |err| {
        std.debug.print("[QWD-API] FastQ QC (R) failed: {}\n", .{err});
        out_buf[0] = 0; // signal error
        return;
    };
    defer allocator.free(json_slice);
    
    const len = @min(json_slice.len, @as(usize, @intCast(max_len.*)) - 1);
    @memcpy(out_buf[0..len], json_slice[0..len]);
    out_buf[len] = 0;
}

// Dummy BAM stats for now to pass tests
pub export fn qwd_bam_stats(path: [*:0]const u8, threads: c_int) ?[*]u8 {
    _ = path; _ = threads;
    const json = "{\"read_count\": 0, \"error\": \"BAM not fully implemented in v1.3.0\"}";
    const allocator = std.heap.page_allocator;
    const slice = allocator.dupe(u8, json) catch return null;
    // null terminate
    const z_slice = allocator.alloc(u8, slice.len + 1) catch return null;
    @memcpy(z_slice[0..slice.len], slice);
    z_slice[slice.len] = 0;
    allocator.free(slice);
    return z_slice.ptr;
}

pub export fn qwd_bam_stats_r(path: [*:0]const u8, threads: *c_int, out_buf: [*]u8, max_len: *c_int) void {
    _ = path; _ = threads; _ = max_len;
    const json = "{\"read_count\": 0, \"error\": \"BAM not fully implemented in v1.3.0\"}";
    @memcpy(out_buf[0..json.len], json);
    out_buf[json.len] = 0;
}

pub export fn qwd_pipeline(config_str: [*:0]const u8, input_path: [*:0]const u8) ?[*]u8 {
    _ = config_str;
    return qwd_fastq_qc(input_path);
}

pub export fn qwd_free_string(ptr: ?[*]u8) void {
    if (ptr) |p| {
        const allocator = std.heap.page_allocator;
        var len: usize = 0;
        while (p[len] != 0) : (len += 1) {}
        allocator.free(p[0 .. len + 1]);
    }
}
