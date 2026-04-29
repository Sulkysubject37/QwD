const std = @import("std");
const ordered_slots = @import("ordered_slots");
const proxy_reader_mod = @import("proxy_reader");
const bgzf_native_reader = @import("bgzf_native_reader");
const reader_interface = @import("reader_interface");
const deflate_impl = @import("deflate_impl");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var iter = init.minimal.args.iterate();

    _ = iter.next(); // skip exe
    const path = iter.next() orelse {
        std.debug.print("Usage: diag_io <file>\n", .{});
        return;
    };

    std.debug.print("[Diag IO] Opening {s}...\n", .{path});
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), init.io, path, .{});
    defer file.close(init.io);

    // Setup Proxy Infrastructure
    var slots = try ordered_slots.SlotManager.init(allocator, 16, 128 * 1024);
    defer slots.deinit();

    // 1. Start a simple feeder thread
    const FeederCtx = struct {
        file: std.Io.File,
        slots: *ordered_slots.SlotManager,
        allocator: std.mem.Allocator,
        io: std.Io,
    };
    const feeder_ctx = FeederCtx{ .file = file, .slots = slots, .allocator = allocator, .io = init.io };

    const feeder = try std.Thread.spawn(.{}, struct {
        fn run(ctx: FeederCtx) void {
            std.debug.print("[Feeder] Started.\n", .{});
            const reader_ctx = reader_interface.Reader.IoReaderContext{
                .file = ctx.file,
                .io = ctx.io,
            };
            const reader = reader_interface.Reader.fromIoFile(&reader_ctx);
            var bgzf = bgzf_native_reader.BgzfNativeReader.init(ctx.allocator) catch return;
            var count: usize = 0;
            while (bgzf.nextBlock(reader) catch null) |block| {
                const slot = ctx.slots.acquireSlotForAssign();
                slot.compressed_data = block.compressed_data;
                ctx.slots.commitAssign();
                count += 1;
                if (count % 1000 == 0) std.debug.print("[Feeder] Block {d}\n", .{count});
            }
            ctx.slots.signalFeederDone();
            std.debug.print("[Feeder] Done. Total blocks: {d}\n", .{count});
        }
    }.run, .{feeder_ctx});

    // 2. Start a simple decompression worker
    const WorkerCtx = struct {
        slots: *ordered_slots.SlotManager,
    };
    const worker_ctx = WorkerCtx{ .slots = slots };

    const worker = try std.Thread.spawn(.{}, struct {
        fn run(ctx: WorkerCtx) void {
            std.debug.print("[Worker] Started.\n", .{});
            while (true) {
                const slot = ctx.slots.getSlotForDecompression() orelse {
                    if (ctx.slots.is_feeder_done) break;
                    std.Thread.yield() catch {};
                    continue;
                };
                const actual = deflate_impl.decompress(slot.compressed_data.?, slot.decompressed_data) catch 0;
                slot.decompressed_len = actual;
                ctx.slots.signalSlotReady(slot);
            }
            std.debug.print("[Worker] Done.\n", .{});
        }
    }.run, .{worker_ctx});

    // 3. Main thread reads from ProxyReader
    std.debug.print("[Main] Initializing ProxyReader...\n", .{});
    var proxy = proxy_reader_mod.ProxyReader.init(slots, init.io);
    var reader = proxy.reader();

    var buffer: [128 * 1024]u8 = undefined;
    var total_read: usize = 0;
    std.debug.print("[Main] Reading stream...\n", .{});
    while (true) {
        const n = try reader.read(&buffer);
        if (n == 0) break;
        total_read += n;
        if (total_read % (1024 * 1024) == 0) {
            std.debug.print("[Main] Progress: {d} MB\n", .{total_read / 1024 / 1024});
        }
    }

    std.debug.print("[Main] Finished. Total bytes read: {d}\n", .{total_read});
    feeder.join();
    worker.join();
}
