# Path and run configuration. Every path comes from the command line; nothing is hard-coded.
#
#   Rscript run_all.R <fcs_folder> [output_folder] [--map S1=<file>,S2=<file>,...] [--export-events]
#
# <fcs_folder> is treated as read-only. Outputs default to <project>/outputs.
# --export-events also writes per-event (per-cell) values to <output_folder>/events/.

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}

get_config <- function(args = commandArgs(trailingOnly = TRUE)) {
  export_events <- "--export-events" %in% args
  args <- args[args != "--export-events"]
  map_arg <- NULL
  i <- which(args == "--map")
  if (length(i)) {
    map_arg <- args[i + 1]
    args <- args[-c(i, i + 1)]
  }
  if (length(args) < 1) {
    stop("usage: Rscript run_all.R <fcs_folder> [output_folder] [--map S1=<file>,...]", call. = FALSE)
  }
  input_dir <- normalizePath(args[1], mustWork = TRUE)
  if (!dir.exists(input_dir)) stop("input is not a folder: ", input_dir, call. = FALSE)
  out_dir <- if (length(args) >= 2) args[2] else file.path(PROJECT_DIR, "outputs")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  if (startsWith(paste0(out_dir, "/"), paste0(input_dir, "/"))) {
    stop("output folder must not be inside the read-only input folder", call. = FALSE)
  }
  fig_dir <- file.path(out_dir, "figures")
  dir.create(fig_dir, showWarnings = FALSE)

  manual_map <- NULL
  if (!is.null(map_arg)) {
    kv <- strsplit(strsplit(map_arg, ",", fixed = TRUE)[[1]], "=", fixed = TRUE)
    manual_map <- setNames(vapply(kv, `[`, "", 2), toupper(vapply(kv, `[`, "", 1)))
  }

  list(
    input_dir = input_dir,
    out_dir = out_dir,
    fig_dir = fig_dir,
    manual_map = manual_map,
    export_events = export_events,
    raw_parser = file.path(PROJECT_DIR, "py", "fcs_raw_parse.py"),
    python = Sys.getenv("FCS_PYTHON", "python3")
  )
}

# What Kaku et al. 2018 (PLOS ONE, doi:10.1371/journal.pone.0190886) say each supplementary file is.
PAPER_TABLE <- data.frame(
  label = c("S1", "S2", "S3", "S4"),
  paper_sample = c(4, 13, 16, 18),
  diagnosis = c("adenocarcinoma", "adenocarcinoma", "mesothelioma", "adenocarcinoma"),
  rule1 = c("+", "+", "-", "-"),
  rule2 = c("+", "-", "+", "-"),
  stringsAsFactors = FALSE
)
