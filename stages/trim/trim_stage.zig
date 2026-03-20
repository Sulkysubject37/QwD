const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const TrimStage = struct {
    adapter_sequence: []const u8,
    reads_seen: usize = 0,
    reads_trimmed: usize = 0,

    pub fn init(adapter: []const u8) TrimStage {
        return TrimStage{
            .adapter_sequence = adapter,
        };
    }

    pub fn process(ptr: *anyopaque, read: *const parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        self.reads_seen += 1;

        if (std.mem.endsWith(u8, read.seq, self.adapter_sequence)) {
            const new_len = read.seq.len - self.adapter_sequence.len;
            var mut_read = @constCast(read);
            mut_read.seq = mut_read.seq[0..new_len];
            mut_read.qual = mut_read.qual[0..new_len];
            self.reads_trimmed += 1;
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Trim Report (adapter={s}):\n", .{self.adapter_sequence}) catch {};
        writer.print("  Reads seen:    {d}\n", .{self.reads_seen}) catch {};
        writer.print("  Reads trimmed: {d}\n", .{self.reads_trimmed}) catch {};
    }

    pub fn stage(self: *@This()) stage_mod.Stage {
        return .{
            .ptr = self,
            .vtable = &.{
                .process = process,
                .finalize = finalize,
                .report = report,
            },
        };
    }
};
