const std = @import("std");

/// Represents a single alignment record from a BAM file.
pub const AlignmentRecord = struct {
    flag: u16,
    reference_id: i32,
    position: i32,
    mapping_quality: u8,
    cigar: []const u8,
    sequence: []const u8,
    quality: []const u8,
    template_length: i32,
};

/// Simulation for streaming BAM records.
pub const BamReader = struct {
    reader: std.io.AnyReader,
    allocator: std.mem.Allocator,
    buffer: []u8,
    record_count: usize = 0,
    max_records: usize = 50000,
    prng: std.rand.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, reader: std.io.AnyReader) !BamReader {
        return BamReader{
            .reader = reader,
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, 65536),
            .prng = std.rand.DefaultPrng.init(42),
        };
    }

    pub fn deinit(self: *BamReader) void {
        self.allocator.free(self.buffer);
    }

    pub fn next(self: *BamReader, record_buffer: []u8) !?AlignmentRecord {
        _ = record_buffer;
        if (self.record_count >= self.max_records) return null;
        self.record_count += 1;

        const random = self.prng.random();
        
        // Simulate mapped vs unmapped (10% unmapped)
        const is_unmapped = random.float(f32) < 0.1;
        
        if (is_unmapped) {
            return AlignmentRecord{
                .flag = 4,
                .reference_id = -1,
                .position = -1,
                .mapping_quality = 0,
                .cigar = "",
                .sequence = "ACGT",
                .quality = "IIII",
                .template_length = 0,
            };
        } else {
            // Simulate MAPQ (0-60)
            const mapq = random.uintAtMost(u8, 60);
            
            // Simulate CIGAR (M, I, D, S)
            const cigar = if (random.float(f32) < 0.05) "90M5S" else "100M";
            
            // Simulate paired vs single (80% paired)
            var flag: u16 = 0;
            var tlen: i32 = 0;
            if (random.float(f32) < 0.8) {
                flag |= 1; // paired
                flag |= 2; // proper pair
                tlen = @intCast(random.intRangeAtMost(i32, 200, 600));
            }

            return AlignmentRecord{
                .flag = flag,
                .reference_id = 1,
                .position = @intCast(random.intRangeAtMost(i32, 1, 1000000)),
                .mapping_quality = mapq,
                .cigar = cigar,
                .sequence = "A" ** 100,
                .quality = "I" ** 100,
                .template_length = tlen,
            };
        }
    }
};
