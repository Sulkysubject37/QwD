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
    allocator: std.mem.Allocator,
    file: std.Io.File,
    io: std.Io,
    buffer: [65536]u8 = undefined,
    record_count: usize = 0,
    max_records: usize = 50000,
    prng: std.Random.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, file: std.Io.File, io: std.Io) !BamReader {
        return BamReader{
            .file = file,
            .io = io,
            .allocator = allocator,
            .prng = std.Random.DefaultPrng.init(42),
        };
    }

    pub fn deinit(self: *BamReader) void {
        _ = self;
    }

    pub fn next(self: *BamReader) !?AlignmentRecord {
        if (self.record_count >= self.max_records) return null;
        
        // Ensure reader is usable (even if simulation for now)
        _ = self.file.reader(self.io, &self.buffer);
        
        self.record_count += 1;

        const r = self.prng.random();
        return AlignmentRecord{
            .flag = r.int(u16),
            .reference_id = r.intRangeAtMost(i32, 0, 22),
            .position = r.intRangeAtMost(i32, 0, 1000000),
            .mapping_quality = r.int(u8),
            .cigar = "150M",
            .sequence = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT",
            .quality = "IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII",
            .template_length = r.intRangeAtMost(i32, 0, 500),
        };
    }
};
