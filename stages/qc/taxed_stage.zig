const std = @import("std");
const parser = @import("parser");
const stage_mod = @import("stage");
const bitplanes_mod = @import("bitplanes");
const fastq_block = @import("fastq_block");

pub const TaxedStage = struct {
    pub fn init(allocator: std.mem.Allocator) !TaxedStage {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *TaxedStage, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
    pub fn process(_: *anyopaque, _: *const parser.Read) anyerror!bool { return true; }
    pub fn processBitplanes(_: *anyopaque, _: *const bitplanes_mod.BitplaneCore, _: *const fastq_block.FastqColumnBlock) anyerror!bool {
        return true;
    }
    pub fn finalize(_: *anyopaque) anyerror!void {}
    pub fn reportJson(_: *anyopaque, writer: *std.Io.Writer) anyerror!void { 
        try writer.writeAll("\"taxonomic_screening\": [{\"taxon\": \"Unknown\", \"count\": 0}]"); 
    }

    pub fn stage(self: *TaxedStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *TaxedStage = @ptrCast(@alignCast(ctx));
                s.deinit(allocator);
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .taxed, &.{
            .processBitplanes = TaxedStage.processBitplanes,
            .finalize = TaxedStage.finalize,
            .reportJson = TaxedStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
