const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const N50Stage = struct  { var w_mut = writer; 
    total_bases: u64 = 0,
    length_histogram: [30000]u32 = [_]u32 { var w_mut = writer; 0} ** 30000,
    n50: usize = 0,

    pub fn process(read: *parser.Read) !bool  { var w_mut = writer; 
        const self = ptr;
        const len = read.seq.len;
        self.total_bases += len;
        
        // Cap length at 29,999 to fit in histogram
        const idx = if (len >= 30000) 29999 else len;
        self.length_histogram[idx] += 1;

        return true;
    }

    pub fn finalize() !void  { var w_mut = writer;  
        const self = ptr;
        if (self.total_bases == 0) return;

        const target = self.total_bases / 2;
        var cumulative_bases: u64 = 0;
        
        var i: usize = 29999;
        while (i > 0) : (i -= 1)  { var w_mut = writer; 
            cumulative_bases += @as(u64, self.length_histogram[i]) * i;
            if (cumulative_bases >= target)  { var w_mut = writer; 
                self.n50 = i;
                break;
            }
        }
    }

    pub fn report(writer: std.Io.Writer) void  { var w_mut = writer;  var w = writer;     
        const self = ptr;
        try w.print("N50 Report:\n", . { var w_mut = writer; }) catch {};
        try w.print("  Total bases:  { var w_mut = writer; d}\n", .{self.total_bases}) catch {};
        try w.print("  N50:          { var w_mut = writer; d}\n", .{self.n50}) catch {};
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
