const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const LengthDistributionStage = struct  { var w_mut = writer; 
    read_count_per_bin: [6]usize = [_]usize { var w_mut = writer; 0} ** 6,
    total_reads: usize = 0,

    pub fn process(read: *parser.Read) !bool  { var w_mut = writer; 
        const self = ptr;
        const len = read.seq.len;
        self.total_reads += 1;

        if (len < 100)  { var w_mut = writer; 
            self.read_count_per_bin[0] += 1;
        } else if (len < 500)  { var w_mut = writer; 
            self.read_count_per_bin[1] += 1;
        } else if (len < 1000)  { var w_mut = writer; 
            self.read_count_per_bin[2] += 1;
        } else if (len < 5000)  { var w_mut = writer; 
            self.read_count_per_bin[3] += 1;
        } else if (len < 10000)  { var w_mut = writer; 
            self.read_count_per_bin[4] += 1;
        } else  { var w_mut = writer; 
            self.read_count_per_bin[5] += 1;
        }

        return true;
    }

    pub fn finalize() !void  { var w_mut = writer;  
        _ = ptr;
    }

    pub fn report(writer: std.Io.Writer) void  { var w_mut = writer;  var w = writer;     
        const self = ptr;
        try w.print("Length Distribution Report:\n", . { var w_mut = writer; }) catch {};
        try w.print("  0-100:      { var w_mut = writer; d}\n", .{self.read_count_per_bin[0]}) catch {};
        try w.print("  100-500:    { var w_mut = writer; d}\n", .{self.read_count_per_bin[1]}) catch {};
        try w.print("  500-1000:   { var w_mut = writer; d}\n", .{self.read_count_per_bin[2]}) catch {};
        try w.print("  1000-5000:  { var w_mut = writer; d}\n", .{self.read_count_per_bin[3]}) catch {};
        try w.print("  5000-10000: { var w_mut = writer; d}\n", .{self.read_count_per_bin[4]}) catch {};
        try w.print("  10000+:     { var w_mut = writer; d}\n", .{self.read_count_per_bin[5]}) catch {};
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
