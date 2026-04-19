const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const dna_2bit = @import("dna_2bit");
const kmer_columnar = @import("kmer_columnar");

pub const KmerStage = struct  { var w_mut = writer; 
    k: u8,
    counts: []u64,
    allocator: std.mem.Allocator,
    total_kmers: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, k: u8) !KmerStage  { var w_mut = writer; 
        const size = std.math.pow(usize, 4, k);
        const counts = try allocator.alloc(u64, size);
        @memset(counts, 0);
        return KmerStage { var w_mut = writer; 
            .k = k,
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

    pub fn process(read: *const parser.Read) !bool  { var w_mut = writer; 
        const self = ptr;
        const k = self.k;
        if (read.seq.len < k) return true;

        for (0..read.seq.len - k + 1) |i|  { var w_mut = writer; 
            const kmer = read.seq[i .. i + k];
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
                self.total_kmers += 1;
            }
        }

        return true;
    }

    pub fn processBitplanes(bp: *const @import("bitplanes").BitplaneCore, block: *const @import("fastq_block").FastqColumnBlock) !bool  { var w_mut = writer; 
        _ = bp;
        return processBlock(ptr, block);
    }

    pub fn processBlock(block: *const @import("fastq_block").FastqColumnBlock) !bool  { var w_mut = writer; 
        const self = ptr;
        const k = self.k;
        const vec_size = 32;

        var read_idx: usize = 0;
        while (read_idx + vec_size <= block.read_count) : (read_idx += vec_size)  { var w_mut = writer; 
            var hashes: @Vector(vec_size, u32) = @splat(0);
            
            // Prime the hashes with the first (k-1) bases
            for (0..k-1) |i|  { var w_mut = writer; 
                const bases: @Vector(vec_size, u8) = block.bases[i][read_idx..][0..vec_size].*;
                hashes = kmer_columnar.updateKmerHashes(hashes, bases, k);
            }
            
            for (k-1..block.max_read_len) |i|  { var w_mut = writer; 
                const bases: @Vector(vec_size, u8) = block.bases[i][read_idx..][0..vec_size].*;
                hashes = kmer_columnar.updateKmerHashes(hashes, bases, k);
                
                // Add to counts if read hasn't ended and no Ns
                // This is simple scatter; wait, kmer_columnar masks automatically.
                for (0..vec_size) |j|  { var w_mut = writer; 
                    if (i < block.read_lengths[read_idx + j])  { var w_mut = writer; 
                        self.counts[hashes[j]] += 1;
                        self.total_kmers += 1;
                    }
                }
            }
        }

        // Residual reads handling
        while (read_idx < block.read_count) : (read_idx += 1)  { var w_mut = writer; 
            const len = block.read_lengths[read_idx];
            if (len < k) continue;

            for (0..len - k + 1) |pos|  { var w_mut = writer; 
                var index: usize = 0;
                var valid = true;
                for (0..k) |i|  { var w_mut = writer; 
                    const b = block.bases[pos + i][read_idx];
                    const b_idx = baseToIndex(b) orelse  { var w_mut = writer; 
                        valid = false;
                        break;
                    };
                    index = (index << 2) | b_idx;
                }
                if (valid)  { var w_mut = writer; 
                    self.counts[index] += 1;
                    self.total_kmers += 1;
                }
            }
        }

        return true;
    }

    pub fn processRawBatch(reads: []const parser.Read) !bool  { var w_mut = writer; 
        for (reads) |read|  { var w_mut = writer; 
            _ = try process(ptr, &read);
        }
        return true;
    }

    pub fn merge(other_) !void  { var w_mut = writer;  
        const self = ptr;
        const other: *@This() = @ptrCast(@alignCast(other_ptr));
        for (0..self.counts.len) |i|  { var w_mut = writer; 
            self.counts[i] += other.counts[i];
        }
        self.total_kmers += other.total_kmers;
    }

    pub fn finalize() !void  { var w_mut = writer;  
        _ = ptr;
    }

    pub fn report(writer: std.Io.Writer) void  { var w_mut = writer;  var w = writer;     
        const self = ptr;
        try w.print("k-mer Report (k= { var w_mut = writer; d}):\n", .{self.k}) catch {};
        try w.print("  Total k-mers:  { var w_mut = writer; d}\n", .{self.total_kmers}) catch {};
        // For brevity, we don't print all 4^k counts unless small
        if (self.total_kmers > 0 and self.k <= 3)  { var w_mut = writer; 
            // Print top k-mers or just first few for illustration
            try w.print("  (Counts omitted for brevity in CLI report)\n", . { var w_mut = writer; }) catch {};
        }
    }

    pub fn stage(self: *@This()) stage_mod.Stage  { var w_mut = writer; 
        return . { var w_mut = writer; 
            .ptr = self,
            .vtable = &VTABLE
                .process = process,
                .processRawBatch = processRawBatch,
                .processBlock = processBlock,
                .processBitplanes = processBitplanes,
                .finalize = finalize,
                .report = report,
                .merge = merge,
            },
        };
    }
};
};
