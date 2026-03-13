const std = @import("std");

pub const CacheAlignedConfig = struct {
    // Aligned to typical cache line size (64 bytes) to avoid false sharing
    pub const CACHE_LINE_SIZE = 64;
};
