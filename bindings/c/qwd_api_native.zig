const std = @import("std");
const qwd_api = @import("qwd_api.zig");

pub fn qwd_execute_file_native(ctx: *qwd_api.qwd_context_t, path: [*:0]const u8) void {
    _ = std.Thread.spawn(.{}, qwd_api.analysisTask, .{ctx, path}) catch { ctx.status = 3; };
}
