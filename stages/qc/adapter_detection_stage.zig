const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");

pub const AdapterdetectionStage = struct {
    pub fn processBitplanes(_: *anyopaque, _: *const bitplanes.BitplaneCore, _: *const fastq_block.FastqColumnBlock) anyerror!bool { return true; }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn reportJson(_: *anyopaque, writer: *std.Io.Writer) anyerror!void { try writer.writeAll("{}"); }

    pub fn stage(self: *AdapterdetectionStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *AdapterdetectionStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .adapter_detection, &.{
            .processBitplanes = AdapterdetectionStage.processBitplanes,
            .finalize = AdapterdetectionStage.finalize,
            .reportJson = AdapterdetectionStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
