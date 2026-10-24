# Entry point: characterise every FCS file in a folder.
#
#   Rscript run_all.R <fcs_folder> [output_folder] [--map S1=<file>,S2=<file>,...] [--export-events]

.f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
PROJECT_DIR <- normalizePath(dirname(.f))
source(file.path(PROJECT_DIR, "R", "paths.R"))
cfg <- get_config()
cat("input :", cfg$input_dir, "(read-only)\noutput:", cfg$out_dir, "\n")

for (s in c("01_inspect_header.R", "02_read_and_summarise.R", "03_plots.R", "04_schema_report.R")) {
  source(file.path(PROJECT_DIR, "R", s))
}
cat("\nDone. Report:", file.path(cfg$out_dir, "report.md"), "\n")
