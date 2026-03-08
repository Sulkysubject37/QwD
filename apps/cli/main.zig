const std = @import("std");
const parser_mod = @import("parser");
const scheduler_mod = @import("scheduler");
const allocator_mod = @import("allocator");
const qc_mod = @import("qc");
const gc_mod = @import("gc");
const length_mod = @import("length");
const metrics_mod = @import("metrics");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var qwd_alloc = allocator_mod.createArena(allocator);
    defer allocator_mod.destroyArena(&qwd_alloc);
    const arena_allocator = qwd_alloc.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} qc <fastq_file>\n", .{args[0]});
        return;
    }

    const command = args[1];
    const file_path = args[2];

    if (!std.mem.eql(u8, command, "qc")) {
        std.debug.print("Unknown command: {s}\n", .{command});
        std.debug.print("Usage: {s} qc <fastq_file>\n", .{args[0]});
        return;
    }

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    const reader = buffered_reader.reader().any();

    var parser = try parser_mod.FastqParser.init(allocator, reader, 65536);
    defer parser.deinit();

    var scheduler = scheduler_mod.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Initialize and register stages
    var qc_stage = qc_mod.QcStage{};
    var gc_stage = gc_mod.GcStage{};
    var length_stage = length_mod.LengthStage{};

    try scheduler.registerStage(qc_stage.stage());
    try scheduler.registerStage(gc_stage.stage());
    try scheduler.registerStage(length_stage.stage());

    const record_buffer = try arena_allocator.alloc(u8, 65536);

    while (try parser.next(record_buffer)) |read| {
        try scheduler.process(read);
    }

    try scheduler.finalize();
    metrics_mod.printSummary(&scheduler);
}
