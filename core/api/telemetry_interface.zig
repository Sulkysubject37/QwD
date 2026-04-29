const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");

pub const TelemetryHookFn = *const fn (
    block: *const fastq_block.FastqColumnBlock, 
    bp: *const bitplanes.BitplaneCore,
    header: [*:0]const u8,
    thread_id: usize,
) callconv(.c) void;
