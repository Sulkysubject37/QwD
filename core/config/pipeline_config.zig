const std = @import("std");

pub const PipelineConfig = struct {
    pipeline: [][]const u8,

    pub fn parseJson(allocator: std.mem.Allocator, json_data: []const u8) !std.json.Parsed(PipelineConfig) {
        return std.json.parseFromSlice(PipelineConfig, allocator, json_data, .{});
    }
};
