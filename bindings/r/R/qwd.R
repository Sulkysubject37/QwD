#' QwD FASTQ QC
#' @param fastq_path Path to FASTQ file
#' @param approx Boolean, whether to use probabilistic approx mode
#' @param threads Number of threads to use (0 for auto)
#' @param gzip_mode Decompression engine: 'auto', 'libdeflate', 'qwd', 'compat'
#' @param ... Additional arguments (deprecated 'fast' supported for backward compatibility)
#' @return A list of metrics
#' @export
qwd_qc <- function(fastq_path, approx = FALSE, threads = 0, gzip_mode = "auto", ...) {
  # Handle backward compatibility for 'fast'
  args <- list(...)
  if ("fast" %in% names(args)) {
    approx <- args$fast
  }

  lib_name <- "qwd"
  lib_file <- if (.Platform$OS.type == "windows") "qwd.dll" else if (Sys.info()["sysname"] == "Darwin") "libqwd.dylib" else "libqwd.so"
  
  # Try to find library
  possible_paths <- c(lib_file, file.path("zig-out", "lib", lib_file), file.path("zig-out", "bin", lib_file))
  path <- ""
  for (p in possible_paths) {
    if (file.exists(p)) { path <- p; break }
  }
  
  if (path == "") stop("QwD shared library not found")
  
  dyn.load(path)
  
  # Map gzip_mode to index
  gz_map <- c("auto" = 0, "native" = 1, "qwd" = 1, "libdeflate" = 2, "chunked" = 3, "compat" = 4)
  gz_idx <- if (gzip_mode %in% names(gz_map)) gz_map[gzip_mode] else 0

  # Allocate 2MB buffer
  max_len <- 2 * 1024 * 1024
  res_buf <- raw(max_len)

  sym <- getNativeSymbolInfo("qwd_fastq_qc_ex_r")
  res <- .C(sym, 
            path = as.character(fastq_path), 
            threads = as.integer(threads), 
            mode = as.integer(if(approx) 1 else 0),
            gzip_mode = as.integer(gz_idx),
            out = res_buf, 
            max_len = as.integer(max_len))
  
  json_str <- rawToChar(res$out[res$out != as.raw(0)])
  
  return(jsonlite::fromJSON(json_str))
}

#' QwD BAM Stats
#' @param bam_path Path to BAM file
#' @param threads Number of threads to use (default 1)
#' @return A list of alignment metrics
#' @export
qwd_bamstats <- function(bam_path, threads = 1) {
  lib_name <- "qwd"
  lib_file <- if (.Platform$OS.type == "windows") "qwd.dll" else if (Sys.info()["sysname"] == "Darwin") "libqwd.dylib" else "libqwd.so"
  
  possible_paths <- c(lib_file, file.path("zig-out", "lib", lib_file), file.path("zig-out", "bin", lib_file))
  path <- ""
  for (p in possible_paths) {
    if (file.exists(p)) { path <- p; break }
  }
  
  if (path == "") stop("QwD shared library not found")
  
  dyn.load(path)
  sym <- getNativeSymbolInfo("qwd_bam_stats_r")
  
  max_len <- 2 * 1024 * 1024
  res_buf <- raw(max_len)
  
  res <- .C(sym, 
            path = as.character(bam_path), 
            threads = as.integer(threads),
            out = res_buf, 
            max_len = as.integer(max_len))
  json_str <- rawToChar(res$out[res$out != as.raw(0)])
  
  return(jsonlite::fromJSON(json_str))
}
