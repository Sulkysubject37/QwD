const std = @import("std");
const stage_mod = @import("stage");
const fastq_block = @import("fastq_block");
const bitplanes_mod = @import("bitplanes");

pub const NucleotidecompositionStage = struct {
    a_count: usize = 0,
    c_count: usize = 0,
    g_count: usize = 0,
    t_count: usize = 0,
    n_count: usize = 0,
    total_bases: usize = 0,

    pub fn processBitplanes(ptr: *anyopaque, bp: *const bitplanes_mod.BitplaneCore, block: *const fastq_block.FastqColumnBlock) anyerror!bool {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const read_count = block.read_count;
        if (read_count == 0) return true;

        var fused: bitplanes_mod.BitplaneCore.FusedResults = .{};
        bp.computeFusedInto(read_count, &fused);
        
        self.a_count += fused.a_count;
        self.c_count += fused.c_count;
        self.g_count += fused.g_count;
        self.t_count += fused.t_count;
        self.n_count += fused.n_count;
        self.total_bases += fused.total_bases;
        return true;
    }

    pub fn finalize(_: *anyopaque) anyerror!void {}

    pub fn reportJson(ptr: *anyopaque, writer_ptr: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        const writer: *std.Io.Writer = @ptrCast(@alignCast(writer_ptr));
        try writer.print("\"nucleotide_composition\": {{\"A\": {d}, \"C\": {d}, \"G\": {d}, \"T\": {d}, \"N\": {d}, \"total\": {d}}}", .{
            self.a_count, self.c_count, self.g_count, self.t_count, self.n_count, self.total_bases,
        });
    }

    pub fn stage(self: *NucleotidecompositionStage) stage_mod.Stage {
        const Gen = struct {
            fn deinit(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const s: *NucleotidecompositionStage = @ptrCast(@alignCast(ctx));
                allocator.destroy(s);
            }
        };
        return stage_mod.Stage.init(self, .nucleotide_composition, &.{
            .processBitplanes = NucleotidecompositionStage.processBitplanes,
            .finalize = NucleotidecompositionStage.finalize,
            .reportJson = NucleotidecompositionStage.reportJson,
            .deinit = Gen.deinit,
        });
    }
};
