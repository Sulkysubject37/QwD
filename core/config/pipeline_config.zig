const std = @import("std");
const mode_mod = @import("mode");

pub const PipelineConfig = struct {
    pipeline: [][]const u8 = &.{},
    mode: mode_mod.Mode = .exact,
    threads: usize = 1,
    gzip_mode: mode_mod.GzipMode = .auto,
    
    // Biological Parameters
    trim_front: usize = 0,
    trim_tail: usize = 0,
    min_quality: f64 = 0.0,
    adapter_sequence: ?[]const u8 = null,

    pub fn default() PipelineConfig {
        return .{};
    }

    pub fn parseJson(allocator: std.mem.Allocator, json_data: []const u8) !std.json.Parsed(PipelineConfig) {
        return std.json.parseFromSlice(PipelineConfig, allocator, json_data, .{
            .ignore_unknown_fields = true,
        });
    }
};
