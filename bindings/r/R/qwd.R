#' QwD FASTQ QC
#' @param fastq_path Path to FASTQ file
#' @return A list of metrics
#' @export
qwd_qc <- function(fastq_path) {
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
  sym <- getNativeSymbolInfo("qwd_fastq_qc_r")
  
  # Allocate 2MB buffer managed by R's garbage collector
  max_len <- 2 * 1024 * 1024
  res_buf <- raw(max_len)
  
  res <- .C(sym, path = as.character(fastq_path), out = res_buf, max_len = as.integer(max_len))
  json_str <- rawToChar(res$out[res$out != as.raw(0)])
  
  return(jsonlite::fromJSON(json_str))
}
