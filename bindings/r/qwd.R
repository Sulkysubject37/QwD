#' QwD FASTQ QC
#' @param fastq_path Path to FASTQ file
#' @return A list of metrics
#' @export
qwd_qc <- function(fastq_path) {
  lib_name <- "qwd"
  lib_file <- if (.Platform$OS.type == "windows") "qwd.dll" else if (Sys.info()["sysname"] == "Darwin") "libqwd.dylib" else "libqwd.so"
  
  # Try to find library
  possible_paths <- c(lib_file, file.path("zig-out", "lib", lib_file))
  path <- ""
  for (p in possible_paths) {
    if (file.exists(p)) { path <- p; break }
  }
  
  if (path == "") stop("QwD shared library not found")
  
  dyn.load(path)
  res <- .C("qwd_fastq_qc", path = as.character(fastq_path), result = character(1))
  # Note: This is a simplified call pattern for R
  return(jsonlite::fromJSON(res$result))
}
