const std = @import("std");
const ordered_slots = @import("ordered_slots");
const proxy_reader_mod = @import("proxy_reader");
const parser_mod = @import("parser");
const reader_interface = @import("reader_interface");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    std.debug.print("[Test] Starting Reader/Parser isolated test...\n", .{});

    var slots = try ordered_slots.SlotManager.init(allocator, 4, 64 * 1024);
    defer slots.deinit();

    // 1. Mock Feeder thread: Provides uncompressed FASTQ records directly
    const feeder = try std.Thread.spawn(.{}, struct {
        fn run(s: *ordered_slots.SlotManager) void {
            const mock_data = 
                "@READ1\nATGCATGCATGCATGC\n+\nIIIIIIIIIIIIIIII\n" ** 1000;
            
            std.debug.print("[Feeder] Pushing mock data...\n", .{});
            
            const slot = s.acquireSlotForAssign();
            @memcpy(slot.decompressed_data[0..mock_data.len], mock_data);
            slot.decompressed_len = mock_data.len;
            
            // Bypass decompression worker: use commitReady
            s.commitReady();
            
            s.signalFeederDone();
            std.debug.print("[Feeder] Done.\n", .{});
        }
    }.run, .{slots});

    // 2. Main thread: Read via ProxyReader -> FastqParser
    std.debug.print("[Main] Initializing ProxyReader...\n", .{});
    var proxy = proxy_reader_mod.ProxyReader.init(slots, init.io);
    const reader = proxy.reader();
    
    std.debug.print("[Main] Initializing FastqParser...\n", .{});
    var parser = try parser_mod.FastqParser.init(allocator, reader, 32 * 1024);
    defer parser.deinit();

    var count: usize = 0;
    std.debug.print("[Main] Parsing records...\n", .{});
    while (try parser.next()) |read| {
        _ = read;
        count += 1;
        if (count % 100 == 0) std.debug.print("[Main] Record {d}\n", .{count});
    }

    std.debug.print("[Main] Finished. Total records parsed: {d}\n", .{count});
    feeder.join();
}
