const std = @import("std");

// HARDENED C-ABI DEFINITIONS (Shared across all platforms)
pub const qwd_telemetry_t = extern struct {
    thread_count: u32 = 0,
    use_exact_mode: u32 = 0,
    trim_front: u32 = 0,
    trim_tail: u32 = 0,
    min_quality: f32 = 0.0,
    _pad1: u32 = 0,
    memory_bytes: u64 = 0,
    cpu_percent: f32 = 0.0,
    _pad2: u32 = 0,
    read_count: u64 = 0,
    total_bases: u64 = 0,
    gc_count: u64 = 0,
    at_count: u64 = 0,
    n_count: u64 = 0,
    violations: u64 = 0,
    status: u32 = 0,
    cancelled: u32 = 0,
    gc_distribution: [101]u64 = [_]u64{0} ** 101,
    length_distribution: [1000]u64 = [_]u64{0} ** 1000,
    quality_heatmap: [150 * 42]u64 = [_]u64{0} ** (150 * 42),
};

pub const qwd_context_t = extern struct {
    pipeline_ptr: ?*anyopaque = null,
    status: u32 = 0,
    thread_count: u32 = 1,
    use_exact_mode: u32 = 0,
    cancelled: u32 = 0,
    read_count: u64 = 0,
    telemetry_hook: ?*const anyopaque = null,
};
