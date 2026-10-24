# Measure where each cell population sits in the public S1–S4 files, as the reference for the
# healthy (non-malignant pleural effusion) synthetic baseline.
#
#   Rscript R/estimate_reference_populations.R [events_dir] [out_dir]
# Defaults: <project>/outputs/events and <project>/outputs/reference_populations.
#
# Writes:
#   hfbf_cutoff_calibration.csv  per file, the SFL cutoff that reproduces the paper's HF-BF count
#   gate_summary.csv             per file × gate: event share, and median / P10 / P90 per signal
#
# Step 1 (calibration): Table 1 gives WBC# and HF-BF# for each file's sample, so the HF-BF share of
# nucleated cells is HF / (WBC + HF). For each file, find the SFL value t such that the share of
# non-debris events with SFL >= t matches it. If t agrees across files, it is a usable HF-BF cutoff.
#
# Step 2 (gates): rectangular gates, applied in order (an event takes the first gate it matches).
# Bounds come from reading compare_S1_S4.png; the HF-BF bound is the calibrated cutoff.

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
args <- commandArgs(trailingOnly = TRUE)
ev_dir <- if (length(args) >= 1) args[1] else file.path(PROJECT_DIR, "outputs", "events")
out_dir <- if (length(args) >= 2) args[2] else file.path(PROJECT_DIR, "outputs", "reference_populations")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

SIGNALS <- c("SSC", "SFL", "FSC", "FSCW")
DEBRIS_SFL <- 16  # same rule as wdf_populations.R

# Table 1 of Ai et al. 2018 for the four published samples.
PAPER <- data.frame(label = c("S1", "S2", "S3", "S4"), sample = c(4, 13, 16, 18),
                    wbc = c(2526, 344, 358, 277), hfbf = c(1071, 41, 68, 20))
PAPER$hf_share <- PAPER$hfbf / (PAPER$wbc + PAPER$hfbf)

ev <- lapply(setNames(PAPER$label, PAPER$label), function(s)
  read.csv(file.path(ev_dir, sprintf("%s_ds1_events.csv", s)))[, SIGNALS])
cat("Loaded", length(ev), "files,", sum(sapply(ev, nrow)), "events\n")

# ---- Step 1: HF-BF cutoff calibration ----
calib <- do.call(rbind, lapply(PAPER$label, function(s) {
  sfl <- ev[[s]]$SFL[ev[[s]]$SFL >= DEBRIS_SFL]
  target <- PAPER$hf_share[PAPER$label == s]
  t <- unname(quantile(sfl, 1 - target, type = 1))
  data.frame(label = s, paper_hf_share = round(target, 4), sfl_cutoff = t,
             share_at_cutoff = round(mean(sfl >= t), 4))
}))
print(calib, row.names = FALSE)
write.csv(calib, file.path(out_dir, "hfbf_cutoff_calibration.csv"), row.names = FALSE)
HF_SFL <- median(calib$sfl_cutoff)
cat("HF-BF SFL cutoff (median across files):", HF_SFL, "\n")

# ---- Step 2: gates ----
gate_events <- function(d) {
  g <- rep("unassigned", nrow(d))
  rules <- list(
    debris       = d$SFL < DEBRIS_SFL,
    aggregate    = d$FSC >= 255 | d$FSCW >= 60,
    hfbf_band    = d$SFL >= HF_SFL,
    lymphocyte   = d$SSC < 95 & d$SFL < 80,
    neutrophil   = d$SSC >= 140 & d$SFL < 50,
    monocyte     = d$SSC >= 80 & d$SSC < 160 & d$SFL >= 50
  )
  for (nm in rev(names(rules))) g[rules[[nm]]] <- nm  # reverse so the first rule wins
  factor(g, levels = c(names(rules), "unassigned"))
}

summ <- do.call(rbind, lapply(names(ev), function(s) {
  d <- ev[[s]]
  g <- gate_events(d)
  nd <- sum(g != "debris")
  do.call(rbind, lapply(levels(g), function(lv) {
    x <- d[g == lv, , drop = FALSE]
    row <- data.frame(label = s, gate = lv, n = nrow(x),
                      pct_all = round(100 * nrow(x) / nrow(d), 2),
                      pct_cells = if (lv == "debris") NA else round(100 * nrow(x) / nd, 2))
    for (sg in SIGNALS) {
      q <- if (nrow(x)) quantile(x[[sg]], c(0.1, 0.5, 0.9), names = FALSE) else rep(NA, 3)
      row[[paste0(sg, "_p10")]] <- q[1]; row[[paste0(sg, "_med")]] <- q[2]; row[[paste0(sg, "_p90")]] <- q[3]
    }
    row
  }))
}))
write.csv(summ, file.path(out_dir, "gate_summary.csv"), row.names = FALSE)
print(summ[, c("label", "gate", "n", "pct_all", "pct_cells", "SSC_med", "SFL_med", "FSC_med", "FSCW_med")],
      row.names = FALSE)
cat("Wrote", out_dir, "\n")
