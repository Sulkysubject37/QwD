#!/bin/bash
set -e

ZIG="/usr/local/zig/zig"
PROJECT_ROOT=$(pwd)
DASHBOARD_ROOT="$PROJECT_ROOT/apps/dashboard"
SDK_MACOS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
SDK_IOS="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
SDK_SIM="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"

mkdir -p "$DASHBOARD_ROOT/build/macos-arm64"
mkdir -p "$DASHBOARD_ROOT/build/ios-arm64"
mkdir -p "$DASHBOARD_ROOT/build/ios-sim-arm64"
mkdir -p "$DASHBOARD_ROOT/build/ios-sim-x86_64"

echo 'pub const HAVE_LIBDEFLATE = false;' > build_options_manual.zig

# The correct 0.13.0 module syntax: --mod name:deps:path
# Order matters: base modules first, then those that depend on them.
MODS="--mod build_options::build_options_manual.zig \
--mod mode::core/config/mode.zig \
--mod ring_buffer::core/parallel/ring_buffer.zig \
--mod entropy_lut::core/entropy/entropy_lut.zig \
--mod structured_output::core/output/structured_output.zig \
--mod global_allocator::core/memory/global_allocator.zig \
--mod runtime_metrics::core/metrics/runtime_metrics.zig \
--mod simd_ops::core/simd/simd_ops.zig \
--mod column_ops::core/vector/column_ops.zig \
--mod simd_transpose::core/simd/simd_transpose.zig \
--mod vertical_scanner::core/simd/vertical_scanner.zig \
--mod newline_scan::core/simd/newline_scan.zig \
--mod bloom_filter::core/analytics/bloom_filter.zig \
--mod dna_2bit::core/encoding/dna_2bit.zig \
--mod cigar_parser::core/cigar/cigar_parser.zig \
--mod kmer_bitroll::core/simd/kmer_bitroll.zig \
--mod kmer_columnar::core/vector/kmer_columnar.zig \
--mod bit_sieve::core/io/bit_sieve.zig \
--mod bgzf_native_reader::core/io/bgzf_native_reader.zig \
--mod bitplanes::core/columnar/bitplane_core.zig \
--mod bam_reader::io/bam/bam_reader.zig \
--mod huffman:bit_sieve:core/io/huffman_decoder.zig \
--mod lz77::core/io/lz77_engine.zig \
--mod custom_deflate:huffman,lz77,bit_sieve:core/io/custom_deflate.zig \
--mod deflate_impl::core/io/deflate_fallback.zig \
--mod pipeline_config:mode:core/config/pipeline_config.zig \
--mod fastq_block:simd_transpose:core/columnar/fastq_block.zig \
--mod deflate_wrapper:deflate_impl,custom_deflate,build_options:core/io/deflate_wrapper.zig \
--mod gzip_reader:mode,custom_deflate,deflate_wrapper,ring_buffer:core/io/gzip_reader.zig \
--mod block_reader:mode,gzip_reader:core/io/block_reader.zig \
--mod parser:mode,newline_scan,block_reader:core/parser/parser.zig \
--mod stage:parser,fastq_block,bitplanes:core/stage/stage.zig \
--mod bam_stage:bam_reader:core/stage/bam_stage.zig \
--mod chunk_builder:parser,block_reader:core/batch/chunk_builder.zig \
--mod bgzf_chunk_builder:bgzf_native_reader:core/batch/bgzf_chunk_builder.zig \
--mod scheduler:parser,stage:core/scheduler/scheduler.zig \
--mod bam_scheduler:bam_reader,bam_stage:core/scheduler/bam_scheduler.zig \
--mod mapq_dist:bam_reader,bam_stage,cigar_parser:stages/alignment/mapq_distribution_stage.zig \
--mod insert_size:bam_reader,bam_stage,cigar_parser:stages/alignment/insert_size_stage.zig \
--mod error_rate:bam_reader,bam_stage,cigar_parser:stages/alignment/error_rate_stage.zig \
--mod coverage:bam_reader,bam_stage,cigar_parser:stages/alignment/coverage_stage.zig \
--mod soft_clip:bam_reader,bam_stage,cigar_parser:stages/alignment/soft_clip_stage.zig \
--mod alignment_stats:bam_reader,bam_stage,cigar_parser:stages/alignment/alignment_stats_stage.zig \
--mod n_statistics:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/n_statistics_stage.zig \
--mod per_base_quality:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/per_base_quality_stage.zig \
--mod qc_length_dist:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/length_distribution_stage.zig \
--mod duplication:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output,bloom_filter:stages/qc/duplication_stage.zig \
--mod qc_adapter_detect:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/adapter_detection_stage.zig \
--mod kmer:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output,kmer_columnar:stages/kmer/kmer_stage.zig \
--mod quality_dist:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/quality_dist_stage.zig \
--mod trim:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/trim/trim_stage.zig \
--mod taxed:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output,kmer_bitroll,kmer_columnar,dna_2bit:stages/qc/taxed_stage.zig \
--mod nucleotide_composition:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/nucleotide_composition_stage.zig \
--mod kmer_spectrum:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output,kmer_bitroll,kmer_columnar,dna_2bit:stages/qc/kmer_spectrum_stage.zig \
--mod filter:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/filter/filter_stage.zig \
--mod gc_distribution:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/gc_distribution_stage.zig \
--mod gc:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/gc/gc_stage.zig \
--mod overrepresented:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/overrepresented_stage.zig \
--mod qc:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/qc_stage.zig \
--mod basic_stats:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output:stages/qc/basic_stats_stage.zig \
--mod qc_entropy:stage,parser,fastq_block,bitplanes,mode,simd_ops,column_ops,structured_output,entropy_lut:stages/qc/entropy_stage.zig \
--mod parallel_scheduler:parser,stage,ring_buffer,block_reader,mode,custom_deflate,deflate_wrapper,fastq_block,bitplanes,vertical_scanner:core/parallel/parallel_scheduler.zig \
--mod bam_pipeline:bam_reader,bam_scheduler,bam_stage,structured_output,mapq_dist,insert_size,error_rate,coverage,soft_clip,alignment_stats:core/pipeline/bam_pipeline.zig \
--mod pipeline:parallel_scheduler,scheduler,block_reader,parser,mode,pipeline_config,stage,bgzf_native_reader,bgzf_chunk_builder,bloom_filter,structured_output,n_statistics,per_base_quality,qc_length_dist,duplication,qc_adapter_detect,kmer,quality_dist,trim,taxed,nucleotide_composition,kmer_spectrum,filter,gc_distribution,gc,overrepresented,qc,basic_stats,qc_entropy:core/pipeline/pipeline.zig"

DEPS="--deps pipeline,parser,mode,entropy_lut,bam_pipeline,bam_reader,structured_output,pipeline_config,global_allocator,runtime_metrics,chunk_builder,bgzf_chunk_builder,bgzf_native_reader,build_options"

build_all() {
    local target=$1
    local sdk=$2
    local out=$3
    
    echo "Building for $target..."
    $ZIG build-lib $MODS $DEPS bindings/c/qwd_api.zig \
        -target "$target" \
        -O ReleaseFast \
        -lc --sysroot "$sdk" \
        -femit-bin="$out"
}

build_all "arm64-macos" "$SDK_MACOS" "$DASHBOARD_ROOT/build/macos-arm64/libqwd.a"
build_all "aarch64-ios" "$SDK_IOS" "$DASHBOARD_ROOT/build/ios-arm64/libqwd.a"
build_all "aarch64-ios-simulator" "$SDK_SIM" "$DASHBOARD_ROOT/build/ios-sim-arm64.a"
build_all "x86_64-ios-simulator" "$SDK_SIM" "$DASHBOARD_ROOT/build/ios-sim-x86_64.a"

echo "Combining Simulator libraries..."
lipo -create "$DASHBOARD_ROOT/build/ios-sim-arm64.a" "$DASHBOARD_ROOT/build/ios-sim-x86_64.a" -output "$DASHBOARD_ROOT/build/ios-sim-universal/libqwd.a"

echo "Creating XCFramework..."
FRAMEWORK_DIR="$DASHBOARD_ROOT/Frameworks"
XCFRAMEWORK="$FRAMEWORK_DIR/QwD.xcframework"
rm -rf "$XCFRAMEWORK"
mkdir -p "$FRAMEWORK_DIR"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -create-xcframework \
    -library "$DASHBOARD_ROOT/build/macos-arm64/libqwd.a" \
    -headers "$DASHBOARD_ROOT/include/qwd" \
    -library "$DASHBOARD_ROOT/build/ios-arm64/libqwd.a" \
    -headers "$DASHBOARD_ROOT/include/qwd" \
    -library "$DASHBOARD_ROOT/build/ios-sim-universal/libqwd.a" \
    -headers "$DASHBOARD_ROOT/include/qwd" \
    -output "$XCFRAMEWORK"

echo "Success! XCFramework generated manually."
