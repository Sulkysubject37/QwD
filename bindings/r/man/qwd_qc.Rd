\name{qwd_qc}
\alias{qwd_qc}
\title{QwD FASTQ QC}
\usage{
qwd_qc(fastq_path)
}
\arguments{
  \item{fastq_path}{Path to FASTQ file}
}
\value{
A list of metrics
}
\description{
QwD FASTQ QC
}
\examples{
\dontrun{
  res <- qwd_qc("path/to/reads.fastq")
}
}
