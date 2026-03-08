const std = @import("std");
const parser_mod = @import("parser");
const scheduler_mod = @import("scheduler");
const allocator_mod = @import("allocator");
const pipeline_mod = @import("pipeline");
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
        std.debug.print("Usage: {s} <qc|pipeline|entropy|n50|quality-decay|adapter-detect> [options] <fastq_file>\n", .{args[0]});
        return;
    }

    const command = args[1];
    var pipeline = pipeline_mod.Pipeline.init(arena_allocator);
    defer pipeline.deinit();

    var file_path: []const u8 = undefined;

    if (std.mem.eql(u8, command, "qc")) {
        file_path = args[2];
        try pipeline.addStageByName("qc");
        try pipeline.addStageByName("gc");
        try pipeline.addStageByName("length");
    } else if (std.mem.eql(u8, command, "pipeline")) {
        if (args.len < 4) {
            std.debug.print("Usage: {s} pipeline <stage1,stage2,...> <fastq_file>\n", .{args[0]});
            return;
        }
        const stage_list = args[2];
        file_path = args[3];

        var it = std.mem.split(u8, stage_list, ",");
        while (it.next()) |stage_name| {
            try pipeline.addStageByName(stage_name);
        }
    } else if (std.mem.eql(u8, command, "entropy")) {
        file_path = args[2];
        try pipeline.addStageByName("entropy");
    } else if (std.mem.eql(u8, command, "n50")) {
        file_path = args[2];
        try pipeline.addStageByName("n50");
    } else if (std.mem.eql(u8, command, "quality-decay")) {
        file_path = args[2];
        try pipeline.addStageByName("quality_decay");
    } else if (std.mem.eql(u8, command, "adapter-detect")) {
        file_path = args[2];
        try pipeline.addStageByName("adapter_detect");
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        return;
    }

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    const reader = buffered_reader.reader().any();

    var parser = try parser_mod.FastqParser.init(allocator, reader, 65536);
    defer parser.deinit();

    const record_buffer = try arena_allocator.alloc(u8, 65536);

    while (try parser.next(record_buffer)) |read| {
        try pipeline.run(read);
    }

    try pipeline.finalize();
    metrics_mod.printSummary(&pipeline.scheduler);
}
