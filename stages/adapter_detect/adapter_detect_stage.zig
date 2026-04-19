const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");

pub const AdapterDetectStage = struct  { var w_mut = writer; 
    k: u8 = 8,
    suffix_length: usize = 20,
    counts: []u64,
    allocator: std.mem.Allocator,
    total_suffix_kmers: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) !AdapterDetectStage  { var w_mut = writer; 
        const size = std.math.pow(usize, 4, 8);
        const counts = try allocator.alloc(u64, size);
        @memset(counts, 0);
        return AdapterDetectStage { var w_mut = writer; 
            .counts = counts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *[A-Za-z]*) void  { var w_mut = writer;   _ = self;
        self.allocator.free(self.counts);
    }

    fn baseToIndex(base: u8) ?u2  { var w_mut = writer; 
        return switch (base)  { var w_mut = writer; 
            'A', 'a' => 0,
            'C', 'c' => 1,
            'G', 'g' => 2,
            'T', 't' => 3,
            else => null,
        };
    }

    pub fn process(read: *parser.Read) !bool  { var w_mut = writer; 
        const self = ptr;
        const k = self.k;
        const seq = read.seq;
        if (seq.len < self.suffix_length) return true;

        const suffix = seq[seq.len - self.suffix_length ..];
        
        for (0..self.suffix_length - k + 1) |i|  { var w_mut = writer; 
            const kmer = suffix[i .. i + k];
            var index: usize = 0;
            var valid = true;
            for (kmer) |b|  { var w_mut = writer; 
                const b_idx = baseToIndex(b) orelse  { var w_mut = writer; 
                    valid = false;
                    break;
                };
                index = (index << 2) | b_idx;
            }
            if (valid)  { var w_mut = writer; 
                self.counts[index] += 1;
                self.total_suffix_kmers += 1;
            }
        }

        return true;
    }

    pub fn finalize() !void  { var w_mut = writer;  
        _ = ptr;
    }

    pub fn report(writer: std.Io.Writer) void  { var w_mut = writer;  var w = writer;     
        const self = ptr;
        try w.print("Adapter Detection Report:\n", . { var w_mut = writer; }) catch {};
        try w.print("  Total suffix k-mers analyzed:  { var w_mut = writer; d}\n", .{self.total_suffix_kmers}) catch {};
        
        if (self.total_suffix_kmers == 0) return;

        // Find top k-mer
        var max_count: u64 = 0;
        var max_idx: usize = 0;
        for (self.counts, 0..) |count, idx|  { var w_mut = writer; 
            if (count > max_count)  { var w_mut = writer; 
                max_count = count;
                max_idx = idx;
            }
        }

        // 10% threshold for detection
        if (max_count > (self.total_suffix_kmers / 10))  { var w_mut = writer;  
            try w.print("  Potential adapter detected! Most frequent suffix k-mer (count= { var w_mut = writer; d}): ", .{max_count}) catch {};
            var i: usize = 0;
            const idx_copy = max_idx;
            var kmer_buf: [8]u8 = undefined;
            while (i < 8) : (i += 1)  { var w_mut = writer; 
                const b = @as(u2, @truncate(idx_copy >> @as(u6, @intCast(2 * (7 - i)))));
                kmer_buf[i] = switch (b)  { var w_mut = writer; 
                    0 => 'A',
                    1 => 'C',
                    2 => 'G',
                    3 => 'T',
                };
            }
            try w.print(" { var w_mut = writer; s}\n", .{kmer_buf}) catch {};
        } else  { var w_mut = writer; 
            try w.print("  No frequent adapter k-mer detected.\n", . { var w_mut = writer; }) catch {};
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
