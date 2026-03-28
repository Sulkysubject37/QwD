#' QwD FASTQ QC
#' @param fastq_path Path to FASTQ file
#' @param fast Boolean, whether to use probabilistic fast mode
#' @param threads Number of threads to use (0 for auto)
#' @return A list of metrics
#' @export
qwd_qc <- function(fastq_path, fast = FALSE, threads = 0) {
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
  
  # Allocate 2MB buffer managed by R's garbage collector
  max_len <- 2 * 1024 * 1024
  res_buf <- raw(max_len)

  if (fast) {
    sym <- getNativeSymbolInfo("qwd_fastq_qc_fast_r")
    res <- .C(sym, path = as.character(fastq_path), threads = as.integer(threads), out = res_buf, max_len = as.integer(max_len))
  } else {
    sym <- getNativeSymbolInfo("qwd_fastq_qc_r")
    res <- .C(sym, path = as.character(fastq_path), out = res_buf, max_len = as.integer(max_len))
  }
  
  json_str <- rawToChar(res$out[res$out != as.raw(0)])
  
  return(jsonlite::fromJSON(json_str))
}

#' QwD BAM Stats
#' @param bam_path Path to BAM file
#' @return A list of alignment metrics
#' @export
qwd_bamstats <- function(bam_path) {
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
  
  res <- .C(sym, path = as.character(bam_path), out = res_buf, max_len = as.integer(max_len))
  json_str <- rawToChar(res$out[res$out != as.raw(0)])
  
  return(jsonlite::fromJSON(json_str))
}
