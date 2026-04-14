const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const TrimStage = struct {
    adapter_sequence: ?[]const u8 = null,
    trim_front: usize = 0,
    trim_tail: usize = 0,
    reads_seen: usize = 0,
    reads_trimmed: usize = 0,

    pub fn init(adapter: ?[]const u8, front: usize, tail: usize) TrimStage {
        return TrimStage{
            .adapter_sequence = adapter,
            .trim_front = front,
            .trim_tail = tail,
        };
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.reads_seen += 1;
        var mut_read = @constCast(read);

        // 1. Static Trimming
        if (self.trim_front > 0 or self.trim_tail > 0) {
            const start = @min(self.trim_front, mut_read.seq.len);
            const end = if (mut_read.seq.len > self.trim_tail) mut_read.seq.len - self.trim_tail else start;
            mut_read.seq = mut_read.seq[start..end];
            mut_read.qual = mut_read.qual[start..end];
            self.reads_trimmed += 1;
        }

        // 2. Adapter Trimming (if any left)
        if (self.adapter_sequence) |adapter| {
            if (std.mem.endsWith(u8, mut_read.seq, adapter)) {
                const new_len = mut_read.seq.len - adapter.len;
                mut_read.seq = mut_read.seq[0..new_len];
                mut_read.qual = mut_read.qual[0..new_len];
                self.reads_trimmed += 1;
            }
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Trim Report (front={d}, tail={d}, adapter={s}):\n", .{ 
            self.trim_front, 
            self.trim_tail, 
            self.adapter_sequence orelse "none" 
        }) catch {};
        writer.print("  Reads seen:    {d}\n", .{self.reads_seen}) catch {};
        writer.print("  Reads trimmed: {d}\n", .{self.reads_trimmed}) catch {};
    }

    pub fn reportJson(ptr: *anyopaque, writer: std.io.AnyWriter) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        try writer.print("\"trim\": {{\"reads_seen\": {d}, \"reads_trimmed\": {d}}}", .{
            self.reads_seen,
            self.reads_trimmed,
        });
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
                .reportJson = reportJson,
            },
        };
    }
};
