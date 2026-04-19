const std = @import("std");

pub const RuntimeMetrics = struct {
    start_time: i64,
    reads_processed: usize,
    
    pub fn start() RuntimeMetrics {
        return RuntimeMetrics{
            .start_time = std.time.milliTimestamp(),
            .reads_processed = 0,
        };
    }
    
    pub fn report(self: *const RuntimeMetrics, writer: std.Io.Writer) void { const w = writer;
        const end_time = std.time.milliTimestamp();
        const elapsed_s = @as(f64, @floatFromInt(end_time - self.start_time)) / 1000.0;
        const throughput = if (elapsed_s > 0) @as(f64, @floatFromInt(self.reads_processed)) / elapsed_s else 0.0;
        
        w.print("Runtime Observability:\n", .{}) catch {};
        w.print("  Total Time: {d:.2}s\n", .{elapsed_s}) catch {};
        w.print("  Throughput: {d:.2} reads/sec\n", .{throughput}) catch {};
    }
};
