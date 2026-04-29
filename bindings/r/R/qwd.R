#' QwD FASTQ QC
#' @export
qwd_qc <- function(fastq_path, approx = FALSE, threads = 0, gzip_mode = "auto", ...) {
  # Robust Path Resolution
  fastq_path <- normalizePath(fastq_path, mustWork = TRUE)

  lib_file <- if (Sys.info()["sysname"] == "Windows") {
    "qwd.dll"
  } else if (Sys.info()["sysname"] == "Darwin") {
    "libqwd.dylib"
  } else {
    "libqwd.so"
  }

  possible_paths <- c(
    lib_file, 
    file.path("zig-out", "lib", lib_file), 
    file.path("zig-out", "bin", lib_file),
    file.path(getwd(), "zig-out", "lib", lib_file)
  )
  
  path <- ""
  for (p in possible_paths) {
    if (file.exists(p)) {
      path <- p
      break
    }
  }
  
  if (path == "") stop("QwD shared library not found. Build it with 'zig build'")
  
  lib <- dyn.load(path)
  
  max_len <- 16 * 1024 * 1024
  res_buf <- raw(max_len)
  
  # .C returns a list of modified arguments. We must capture it.
  res <- .C(getNativeSymbolInfo("qwd_fastq_qc_ex_r", lib), 
            path = as.character(fastq_path), 
            threads = as.integer(threads), 
            mode = as.integer(if(approx) 1 else 0), 
            gzip_mode = as.integer(0), 
            out = res_buf, 
            max_len = as.integer(max_len))
  
  actual_buf <- res$out
  
  # Check if engine returned data (first byte should not be 0)
  if (actual_buf[1] == as.raw(0)) {
    stop("QwD Engine failed to process file or returned an empty report.")
  }

  terminator_idx <- match(as.raw(0), actual_buf)
  if (is.na(terminator_idx) || terminator_idx <= 1) {
    stop("QwD Engine returned an empty report. Check for errors in the engine console.")
  }
  
  json_str <- rawToChar(actual_buf[1:(terminator_idx - 1)])
  return(jsonlite::fromJSON(json_str))
}

#' QwD BAM Statistics
#' @export
qwd_bamstats <- function(bam_path, threads = 0, ...) {
  # Robust Path Resolution
  bam_path <- normalizePath(bam_path, mustWork = TRUE)

  lib_file <- if (Sys.info()["sysname"] == "Windows") {
    "qwd.dll"
  } else if (Sys.info()["sysname"] == "Darwin") {
    "libqwd.dylib"
  } else {
    "libqwd.so"
  }

  possible_paths <- c(
    lib_file, 
    file.path("zig-out", "lib", lib_file), 
    file.path("zig-out", "bin", lib_file),
    file.path(getwd(), "zig-out", "lib", lib_file)
  )
  
  path <- ""
  for (p in possible_paths) {
    if (file.exists(p)) {
      path <- p
      break
    }
  }
  
  if (path == "") stop("QwD shared library not found. Build it with 'zig build'")
  
  dyn.load(path)
  
  max_len <- 16 * 1024 * 1024
  res_buf <- raw(max_len)
  
  res <- .C("qwd_bam_stats_r", 
            path = as.character(bam_path), 
            threads = as.integer(threads), 
            out = res_buf, 
            max_len = as.integer(max_len))
  
  actual_buf <- res$out
  
  if (actual_buf[1] == as.raw(0)) {
    stop("QwD Engine failed to process file or returned an empty report.")
  }

  terminator_idx <- match(as.raw(0), actual_buf)
  if (is.na(terminator_idx) || terminator_idx <= 1) {
    stop("QwD Engine returned an empty report.")
  }
  
  json_str <- rawToChar(actual_buf[1:(terminator_idx - 1)])
  return(jsonlite::fromJSON(json_str))
}
