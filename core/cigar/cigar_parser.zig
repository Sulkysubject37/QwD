const std = @import("std");

pub const CigarStats = struct {
    aligned_length: usize = 0,
    insertions: usize = 0,
    deletions: usize = 0,
    soft_clips: usize = 0,
};

pub fn parseCigar(cigar: []const u8) CigarStats {
    var stats = CigarStats{};
    var num: usize = 0;

    for (cigar) |c| {
        if (c >= '0' and c <= '9') {
            num = num * 10 + (c - '0');
        } else {
            switch (c) {
                'M', '=', 'X' => stats.aligned_length += num,
                'I' => stats.insertions += num,
                'D' => stats.deletions += num,
                'S' => stats.soft_clips += num,
                'H' => {}, // Hard clip doesn't affect sequence length
                else => {},
            }
            num = 0;
        }
    }
    return stats;
}
