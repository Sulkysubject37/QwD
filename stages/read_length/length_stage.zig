const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const LengthStage = struct  { var w_mut = writer; 
    total_reads: usize = 0,
    total_length: u64 = 0,
    min_length: usize = std.math.maxInt(usize),
    max_length: usize = 0,
    mean_length: f64 = 0.0,

    pub fn process(read: *parser.Read) !bool  { var w_mut = writer; 
        const self = ptr;
        const len = read.seq.len;
        self.total_reads += 1;
        self.total_length += len;
        if (len < self.min_length) self.min_length = len;
        if (len > self.max_length) self.max_length = len;
        return true;
    }

    pub fn finalize() !void  { var w_mut = writer;  
        const self = ptr;
        if (self.total_reads > 0)  { var w_mut = writer; 
            self.mean_length = @as(f64, @floatFromInt(self.total_length)) / @as(f64, @floatFromInt(self.total_reads));
        } else  { var w_mut = writer; 
            self.min_length = 0;
        }
    }

    pub fn merge(other_) !void  { var w_mut = writer;  
        const self = ptr;
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        self.total_reads += other.total_reads;
        self.total_length += other.total_length;
        if (other.min_length < self.min_length) self.min_length = other.min_length;
        if (other.max_length > self.max_length) self.max_length = other.max_length;
    }

    pub fn report(writer: std.Io.Writer) void  { var w_mut = writer;  var w = writer;     
        const self = ptr;
        try w.print("Read Length Report:\n", . { var w_mut = writer; }) catch {};
        try w.print("  Mean length:  { var w_mut = writer; d:.2}\n", .{self.mean_length}) catch {};
        try w.print("  Min length:  { var w_mut = writer; d}\n", .{self.min_length}) catch {};
        try w.print("  Max length:  { var w_mut = writer; d}\n", .{self.max_length}) catch {};
    }

    pub fn stage(self: *@This()) stage_mod.Stage  { var w_mut = writer; 
        return . { var w_mut = writer; 
            .ptr = self,
            .vtable = &VTABLE
                .process = process,
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
};
