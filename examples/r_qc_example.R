# QwD R Example
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript r_qc_example.R <file>")
}

# Load the binding
source("bindings/r/R/qwd.R")

fastq_path <- args[1]
cat(sprintf("QwD R Binding Example - Analyzing %s\n", fastq_path))

# Set library path for Dyn.load
Sys.setenv(DYLD_LIBRARY_PATH = paste0(getwd(), "/zig-out/lib"))

start_time <- Sys.time()

# Run QC
cat("Running QC...\n")
metrics <- qwd_qc(fastq_path, threads = 4)

end_time <- Sys.time()
duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat(sprintf("QC Completed in %.4fs\n", duration))
cat(sprintf("Read Count: %d\n", metrics$read_count))
