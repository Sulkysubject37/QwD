const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const QualityDecayStage = struct  { var w_mut = writer; 
    const MAX_POS = 10000;
    quality_sum: [MAX_POS]u64 = [_]u64 { var w_mut = writer; 0} ** MAX_POS,
    base_count: [MAX_POS]u64 = [_]u64 { var w_mut = writer; 0} ** MAX_POS,
    mean_quality: [MAX_POS]f64 = [_]f64 { var w_mut = writer; 0.0} ** MAX_POS,

    pub fn process(read: *parser.Read) !bool  { var w_mut = writer; 
        const self = ptr;
        const limit = if (read.qual.len > MAX_POS) MAX_POS else read.qual.len;

        for (0..limit) |pos|  { var w_mut = writer; 
            const phred = read.qual[pos] - 33;
            self.quality_sum[pos] += phred;
            self.base_count[pos] += 1;
        }

        return true;
    }

    pub fn finalize() !void  { var w_mut = writer;  
        const self = ptr;
        for (0..MAX_POS) |pos|  { var w_mut = writer; 
            if (self.base_count[pos] > 0)  { var w_mut = writer; 
                self.mean_quality[pos] = @as(f64, @floatFromInt(self.quality_sum[pos])) / @as(f64, @floatFromInt(self.base_count[pos]));
            }
        }
    }

    pub fn report(writer: std.Io.Writer) void  { var w_mut = writer;  var w = writer;     
        const self = ptr;
        try w.print("Quality Decay Report (first 10 positions):\n", . { var w_mut = writer; }) catch {};
        const limit = if (MAX_POS > 10) 10 else MAX_POS;
        for (0..limit) |pos|  { var w_mut = writer; 
            if (self.base_count[pos] > 0)  { var w_mut = writer; 
                try w.print("  Pos  { var w_mut = writer; d}: {d:.2}\n", .{ pos, self.mean_quality[pos] }) catch {};
            }
        }
    }

    pub fn stage(self: *@This()) stage_mod.Stage  { var w_mut = writer; 
        return . { var w_mut = writer; 
            .ptr = self,
            .vtable = &VTABLE
                .process = process,
                .finalize = finalize,
                .report = report,
            },
        };
    }
};
};
