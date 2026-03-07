const std = @import("std");
const parser_mod = @import("parser");
const scheduler_mod = @import("scheduler");
const allocator_mod = @import("allocator");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use an arena for faster allocations during the streaming process.
    var qwd_alloc = allocator_mod.createArena(allocator);
    defer allocator_mod.destroyArena(&qwd_alloc);
    const arena_allocator = qwd_alloc.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <fastq_file>\n", .{args[0]});
        return;
    }

    const file_path = args[1];
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    const reader = buffered_reader.reader().any();

    // Initialize parser with a buffer size.
    var parser = try parser_mod.FastqParser.init(allocator, reader, 65536);
    defer parser.deinit();

    var scheduler = scheduler_mod.Scheduler{};

    // Buffer to hold read data slices.
    const record_buffer = try arena_allocator.alloc(u8, 65536);

    while (try parser.next(record_buffer)) |read| {
        try scheduler.process(read);
    }

    std.debug.print("Processed reads: {d}\n", .{scheduler.read_count});
}
