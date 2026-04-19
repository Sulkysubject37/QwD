const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const EntropyStage = struct  { var w_mut = writer; 
    total_reads: usize = 0,
    total_entropy_sum: f64 = 0.0,
    low_complexity_reads: usize = 0,
    mean_entropy: f64 = 0.0,

    pub fn process(read: *parser.Read) !bool  { var w_mut = writer; 
        const self = ptr;
        const len = read.seq.len;
        if (len == 0) return true;

        var base_counts = [_]usize { var w_mut = writer; 0} ** 4;
        for (read.seq) |base|  { var w_mut = writer; 
            switch (base)  { var w_mut = writer; 
                'A', 'a' => base_counts[0] += 1,
                'C', 'c' => base_counts[1] += 1,
                'G', 'g' => base_counts[2] += 1,
                'T', 't' => base_counts[3] += 1,
                else =>  { var w_mut = writer; },
            }
        }

        var entropy: f64 = 0.0;
        const flen = @as(f64, @floatFromInt(len));
        for (base_counts) |count|  { var w_mut = writer; 
            if (count > 0)  { var w_mut = writer; 
                const p = @as(f64, @floatFromInt(count)) / flen;
                entropy -= p * std.math.log2(p);
            }
        }

        self.total_reads += 1;
        self.total_entropy_sum += entropy;

        if (entropy < 1.5)  { var w_mut = writer; 
            self.low_complexity_reads += 1;
        }

        return true;
    }

    pub fn finalize() !void  { var w_mut = writer;  
        const self = ptr;
        if (self.total_reads > 0)  { var w_mut = writer; 
            self.mean_entropy = self.total_entropy_sum / @as(f64, @floatFromInt(self.total_reads));
        }
    }

    pub fn report(writer: std.Io.Writer) void  { var w_mut = writer;  var w = writer;     
        const self = ptr;
        try w.print("Sequence Entropy Report:\n", . { var w_mut = writer; }) catch {};
        try w.print("  Mean entropy:       { var w_mut = writer; d:.4}\n", .{self.mean_entropy}) catch {};
        try w.print("  Low complexity:     { var w_mut = writer; d}\n", .{self.low_complexity_reads}) catch {};
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
