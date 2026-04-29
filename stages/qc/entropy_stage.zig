const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const bitplanes = @import("bitplanes");

pub const EntropyStage = struct {
    pub fn processBitplanes(_: *anyopaque, _: *const bitplanes.BitplaneCore, _: *const fastq_block.FastqColumnBlock) anyerror!bool { return true; }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn reportJson(_: *anyopaque, writer: *std.Io.Writer) anyerror!void { try writer.writeAll("{}"); }

    pub fn stage(self: *EntropyStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *EntropyStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .entropy, &.{
            .processBitplanes = EntropyStage.processBitplanes,
            .finalize = EntropyStage.finalize,
            .reportJson = EntropyStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
