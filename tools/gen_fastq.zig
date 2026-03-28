// tools/gen_fastq.zig — Realistic synthetic FASTQ generator for QwD testing
// Builds standalone: /usr/local/zig/zig run tools/gen_fastq.zig -- test_1M.fastq 1000000
//
// Profiles (proportional):
//   60% — good quality (Q34-36, slight 3' drop)
//   20% — average quality (Q24-28, moderate drop)
//    7% — bad quality (Q14-20, heavy degradation)
//    3% — degraded (ok start → crash after 60%)
//    4% — low complexity (homopolymer / ACAC runs)
//    3% — adapter contaminated (TruSeq Read 1 bleed-in)
//    2% — N-containing reads
//    1% — short reads (30-65bp edge case)
//    3% — PCR/optical duplicates from a pool

const std = @import("std");

// ── Xoshiro256** — fast, high-quality PRNG ─────────────────────────
const Xoshiro256 = struct {
    s: [4]u64,

    fn init(seed: u64) Xoshiro256 {
        // SplitMix64 to init state
        var s = seed;
        var state: [4]u64 = undefined;
        for (&state) |*v| {
            s +%= 0x9e3779b97f4a7c15;
            var z = s;
            z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
            z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
            v.* = z ^ (z >> 31);
        }
        return .{ .s = state };
    }

    fn next(self: *Xoshiro256) u64 {
        const result = std.math.rotl(u64, self.s[1] *% 5, 7) *% 9;
        const t = self.s[1] << 17;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = std.math.rotl(u64, self.s[3], 45);
        return result;
    }

    // Returns float in [0, 1)
    fn float(self: *Xoshiro256) f64 {
        return @as(f64, @floatFromInt(self.next() >> 11)) / @as(f64, 1 << 53);
    }

    // Returns int in [0, n)
    fn uintLessThan(self: *Xoshiro256, n: u64) u64 {
        return self.next() % n;
    }
};

// ── Constants ─────────────────────────────────────────────────────
const BASES = "ACGT";
// ACGT weights ~50% GC: A=24, C=26, G=26, T=24
// Using weighted table of 100 entries
const BASE_TABLE_50: [100]u8 = buildBaseTable(24, 26, 26, 24);
const BASE_TABLE_HI: [100]u8 = buildBaseTable(14, 36, 36, 14); // ~72% GC
const BASE_TABLE_LO: [100]u8 = buildBaseTable(34, 16, 16, 34); // ~32% GC

fn buildBaseTable(wa: u8, wc: u8, wg: u8, wt: u8) [100]u8 {
    var table: [100]u8 = undefined;
    var i: usize = 0;
    for (0..wa) |_| { table[i] = 'A'; i += 1; }
    for (0..wc) |_| { table[i] = 'C'; i += 1; }
    for (0..wg) |_| { table[i] = 'G'; i += 1; }
    for (0..wt) |_| { table[i] = 'T'; i += 1; }
    return table;
}

const ADAPTER = "AGATCGGAAGAGCACACGTCTGAACTCCAGTCA";
const LOW_COMPLEX = [_][]const u8{ "AAAAAAAA", "CCCCCCCC", "ACACACAC", "GCGCGCGC", "ATATATAT" };

// ── Read types ────────────────────────────────────────────────────
const ReadType = enum { good, average, bad, degraded, low_complex, adapter, n_seq, short };

fn selectType(rng: *Xoshiro256) ReadType {
    const r = rng.uintLessThan(1000);
    return if (r < 600) .good
    else if (r < 800) .average
    else if (r < 870) .bad
    else if (r < 900) .degraded
    else if (r < 940) .low_complex
    else if (r < 970) .adapter
    else if (r < 990) .n_seq
    else .short;
}

// ── Sequence generation ───────────────────────────────────────────
fn genSeq(rng: *Xoshiro256, buf: []u8, len: usize, gc_mode: u8) void {
    const table = switch (gc_mode) {
        1 => &BASE_TABLE_HI,
        2 => &BASE_TABLE_LO,
        else => &BASE_TABLE_50,
    };
    for (buf[0..len]) |*b| {
        b.* = table[rng.uintLessThan(100)];
    }
}

fn genLowComplex(rng: *Xoshiro256, buf: []u8, len: usize) void {
    const pattern = LOW_COMPLEX[rng.uintLessThan(LOW_COMPLEX.len)];
    const plen = pattern.len;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        buf[i] = pattern[i % plen];
    }
}

fn genAdapter(rng: *Xoshiro256, buf: []u8, len: usize) void {
    const insert_len = 20 + rng.uintLessThan(@as(u64, len - 20));
    genSeq(rng, buf, insert_len, 0);
    const adp = ADAPTER[0..@min(ADAPTER.len, len - insert_len)];
    @memcpy(buf[insert_len..insert_len + adp.len], adp);
    // Fill any remainder
    for (buf[insert_len + adp.len..len]) |*b| b.* = 'N';
}

fn genNSeq(rng: *Xoshiro256, buf: []u8, len: usize) void {
    genSeq(rng, buf, len, 0);
    const n_count = 5 + rng.uintLessThan(@min(30, len / 4));
    for (0..n_count) |_| {
        buf[rng.uintLessThan(len)] = 'N';
    }
}

// ── Quality generation ────────────────────────────────────────────
fn genQual(rng: *Xoshiro256, buf: []u8, len: usize, profile: ReadType) void {
    for (buf[0..len], 0..) |*q, i| {
        const pos: f64 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(len));
        const noise: i32 = @as(i32, @intCast(rng.uintLessThan(7))) - 3;

        const base_q: i32 = switch (profile) {
            .good => blk: {
                // Q35 start, creeps down to Q31 at 3' end
                break :blk 35 - @as(i32, @intFromFloat(pos * pos * 6.0)) + noise;
            },
            .average => blk: {
                // Q27 start, drops to Q18 at 3' end
                break :blk 27 - @as(i32, @intFromFloat(pos * 12.0)) + noise;
            },
            .bad => blk: {
                // Q20 start, crashes to Q6
                const drop = @as(i32, @intFromFloat(std.math.pow(f64, pos, 1.5) * 16.0));
                break :blk 20 - drop + noise;
            },
            .degraded => blk: {
                // Good until 60%, then collapses
                if (pos < 0.6) {
                    break :blk 30 + noise;
                } else {
                    const collapse = @as(i32, @intFromFloat((pos - 0.6) * 45.0));
                    break :blk 28 - collapse + noise;
                }
            },
            .n_seq => blk: {
                // Noisy bad quality throughout
                break :blk 16 - @as(i32, @intFromFloat(pos * 10.0)) + noise;
            },
            .adapter => blk: {
                // Good insert, sudden drop at adapter start
                if (i < 80) {
                    break :blk 33 + @divTrunc(noise, 2);
                } else {
                    break :blk 14 - @as(i32, @intFromFloat((pos - 0.5) * 15.0)) + noise;
                }
            },
            else => 30 + noise,
        };

        const clamped: u8 = @intCast(@max(2, @min(40, base_q)));
        q.* = 33 + clamped;
    }
}

// ── Main ──────────────────────────────────────────────────────────
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const output_path = if (args.len >= 2) args[1] else "test_1M.fastq";
    const total_reads: u64 = if (args.len >= 3) try std.fmt.parseInt(u64, args[2], 10) else 1_000_000;
    const seed: u64      = if (args.len >= 4) try std.fmt.parseInt(u64, args[3], 10) else 42;

    const stderr = std.io.getStdErr().writer();
    try stderr.print("Generating {d} reads → {s}\n", .{ total_reads, output_path });
    try stderr.print("  Profile: 60%% good / 20%% average / 10%% bad+degraded / 5%% edge-cases\n", .{});

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    // 8MB write buffer — single syscall per flush
    var bw = std.io.bufferedWriter(file.writer());
    const w = bw.writer();

    var rng = Xoshiro256.init(seed);

    // Pre-allocate sequence + quality buffers (max read=150)
    var seq_buf: [200]u8 = undefined;
    var qal_buf: [200]u8 = undefined;
    var id_buf:  [32]u8  = undefined;

    // Small duplicate pool: store up to 5000 good reads
    const POOL_SIZE: usize = 5000;
    const POOL_SEQ_LEN: usize = 130;
    var dupe_pool: [POOL_SIZE][POOL_SEQ_LEN]u8 = undefined;
    var pool_len:  usize = 0;

    for (0..total_reads) |i| {
        const read_type = selectType(&rng);

        // 3% chance of emitting a duplicate from the pool
        if (pool_len > 10 and rng.uintLessThan(100) < 3) {
            const idx = rng.uintLessThan(@as(u64, pool_len));
            const dup_seq = dupe_pool[idx][0..POOL_SEQ_LEN];
            const qual_profile: ReadType = .good;
            genQual(&rng, &qal_buf, POOL_SEQ_LEN, qual_profile);
            const id = try std.fmt.bufPrint(&id_buf, "@read_{d}", .{i});
            try w.print("{s}\n", .{id});
            try w.print("{s}\n+\n", .{dup_seq});
            try w.writeAll(qal_buf[0..POOL_SEQ_LEN]);
            try w.writeByte('\n');
            continue;
        }

        // Determine read length
        const rlen: usize = switch (read_type) {
            .short => 30 + @as(usize, @intCast(rng.uintLessThan(36))),
            else   => 100 + @as(usize, @intCast(rng.uintLessThan(51))),
        };

        // Determine GC bias (2% high-GC, 2% low-GC)
        const gc_mode: u8 = if (rng.uintLessThan(100) < 2) 1
                            else if (rng.uintLessThan(100) < 2) 2
                            else 0;

        // Generate sequence
        switch (read_type) {
            .low_complex => genLowComplex(&rng, &seq_buf, rlen),
            .adapter     => genAdapter(&rng, &seq_buf, rlen),
            .n_seq       => genNSeq(&rng, &seq_buf, rlen),
            else         => genSeq(&rng, &seq_buf, rlen, gc_mode),
        }

        // Quality
        genQual(&rng, &qal_buf, rlen, read_type);

        // Stash good/normal-length reads into dupe pool
        if (read_type == .good and rlen == POOL_SEQ_LEN and pool_len < POOL_SIZE) {
            @memcpy(&dupe_pool[pool_len], seq_buf[0..POOL_SEQ_LEN]);
            pool_len += 1;
        }

        // Write
        const id = try std.fmt.bufPrint(&id_buf, "@read_{d}", .{i});
        try w.writeAll(id);
        try w.writeByte('\n');
        try w.writeAll(seq_buf[0..rlen]);
        try w.writeAll("\n+\n");
        try w.writeAll(qal_buf[0..rlen]);
        try w.writeByte('\n');
    }

    try bw.flush();
    try stderr.print("Done. {d} reads written to {s}\n", .{ total_reads, output_path });
}
