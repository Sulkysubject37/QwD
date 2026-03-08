const std = @import("std");
const bam_reader = @import("bam_reader");
const bam_stage = @import("bam_stage");

pub const InsertSizeStage = struct {
    // Bounded histogram up to 10,000 to keep memory deterministic
    const MAX_INSERT = 10000;
    insert_size_histogram: [MAX_INSERT]usize = [_]usize{0} ** MAX_INSERT,
    sum_insert_size: u64 = 0,
    count: usize = 0,
    min_insert_size: i32 = std.math.maxInt(i32),
    max_insert_size: i32 = 0,
    mean_insert_size: f64 = 0.0,

    pub fn process(ptr: *anyopaque, record: *bam_reader.AlignmentRecord) !bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        
        // Check if paired (1) and properly mapped pair (2)
        if ((record.flag & 1) != 0 and (record.flag & 2) != 0) {
            // template_length can be negative if mate maps to higher pos.
            const tlen = if (record.template_length < 0) -record.template_length else record.template_length;
            if (tlen > 0) {
                if (tlen < self.min_insert_size) self.min_insert_size = tlen;
                if (tlen > self.max_insert_size) self.max_insert_size = tlen;
                self.sum_insert_size += @intCast(tlen);
                self.count += 1;
                
                const idx: usize = if (tlen >= MAX_INSERT) MAX_INSERT - 1 else @intCast(tlen);
                self.insert_size_histogram[idx] += 1;
            }
        }
        return true;
    }

    pub fn finalize(ptr: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        if (self.count > 0) {
            self.mean_insert_size = @as(f64, @floatFromInt(self.sum_insert_size)) / @as(f64, @floatFromInt(self.count));
        } else {
            self.min_insert_size = 0;
        }
    }

    pub fn report(ptr: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        std.debug.print("Insert Size Report:\n", .{});
        std.debug.print("  Pairs analyzed: {d}\n", .{self.count});
        std.debug.print("  Min insert:     {d}\n", .{self.min_insert_size});
        std.debug.print("  Max insert:     {d}\n", .{self.max_insert_size});
        std.debug.print("  Mean insert:    {d:.2}\n", .{self.mean_insert_size});
    }

    pub fn stage(self: *@This()) bam_stage.BamStage {
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
