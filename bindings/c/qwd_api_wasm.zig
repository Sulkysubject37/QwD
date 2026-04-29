// Agnostic WASM shim for qwd_api
const qwd_api = @import("qwd_api.zig");

pub fn qwd_execute_file_native(ctx: *qwd_api.qwd_context_t, path: [*:0]const u8) void {
    // On WASM, we execute synchronously or via worker if implemented later.
    // For Raja Reform, we just ensure it executes.
    qwd_api.analysisTask(ctx, path);
}
