const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const NucleotideCompositionStage = struct {
    const MAX_POS = 10000;
    // 0: A, 1: C, 2: G, 3: T
    base_counts: [MAX_POS][4]u64 = [_][4]u64{[_]u64{0} ** 4} ** MAX_POS,

    pub fn process(ptr: *anyopaque, read: *parser.Read) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const limit = if (read.seq.len > MAX_POS) MAX_POS else read.seq.len;

        for (0..limit) |pos| {
            switch (read.seq[pos]) {
                'A', 'a' => self.base_counts[pos][0] += 1,
                'C', 'c' => self.base_counts[pos][1] += 1,
                'G', 'g' => self.base_counts[pos][2] += 1,
                'T', 't' => self.base_counts[pos][3] += 1,
                else => {},
            }
        }

        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        _ = ptr;
    }

    pub fn report(ptr: *anyopaque, writer: std.io.AnyWriter) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        writer.print("Nucleotide Composition Report (first 5 positions):\n", .{}) catch {};
        const limit = if (MAX_POS > 5) 5 else MAX_POS;
        for (0..limit) |pos| {
            writer.print("  Pos {d}: A={d}, C={d}, G={d}, T={d}\n", .{
                pos,
                self.base_counts[pos][0],
                self.base_counts[pos][1],
                self.base_counts[pos][2],
                self.base_counts[pos][3],
            }) catch {};
        }
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
