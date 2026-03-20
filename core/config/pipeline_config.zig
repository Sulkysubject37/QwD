const std = @import("std");
const mode_mod = @import("mode");

pub const PipelineConfig = struct {
    pipeline: [][]const u8,
    mode: mode_mod.Mode = .EXACT,

    pub fn parseJson(allocator: std.mem.Allocator, json_data: []const u8) !std.json.Parsed(PipelineConfig) {
        return std.json.parseFromSlice(PipelineConfig, allocator, json_data, .{});
    }
};
