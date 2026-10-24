# Fit the WDF population model to each real file, simulate a synthetic file of the same size,
# write it as XN-layout FCS, and compare synthetic with real.
#
#   Rscript R/synth_compare.R <events_folder> <out_folder> [dims]
#
# <events_folder>: per-event CSVs from run_all.R --export-events (S1_ds1_events.csv, ...).
# [dims]: signals the core mixture is fitted on (default SSC,SFL,FSC).
#
# Writes to <out_folder>:
#   fcs/synthetic.s00N.fcs         synthetic FCS, one per real file (re-run run_all.R on this folder)
#   population_weights.csv         share of events per population, real fit
#   comparison_marginals.csv       median / p01 / p99 / sd / % at 0 / % at 255 per signal, real vs synthetic
#   comparison_scores.csv          KS D per signal, 2D histogram overlap per view, classifier AUC
#   figures/<label>_real_vs_synth.png, figures/combined_real_vs_synth.png
#
# Classifier test: k-nearest-neighbours trained to tell real from synthetic events. AUC 0.5 means
# indistinguishable. Two references: real vs real (split halves), and a naive one-Gaussian generator.

.f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
source(file.path(PROJECT_DIR, "R", "wdf_populations.R"))
source(file.path(PROJECT_DIR, "R", "xn_fcs_writer.R"))
suppressPackageStartupMessages({
  library(class)
  library(ggplot2)
  library(cowplot)
})

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% 2:3) stop("usage: Rscript R/synth_compare.R <events_folder> <out_folder> [dims]")
ev_dir <- normalizePath(args[1], mustWork = TRUE)
out_dir <- args[2]
dims <- if (length(args) == 3) strsplit(args[3], ",", fixed = TRUE)[[1]] else c("SSC", "SFL", "FSC")
for (d in c("fcs", "figures")) dir.create(file.path(out_dir, d), recursive = TRUE, showWarnings = FALSE)

files <- sort(list.files(ev_dir, pattern = "^S[0-9]+_ds1_events\\.csv$", full.names = TRUE))
if (!length(files)) stop("no S<n>_ds1_events.csv files in ", ev_dir, call. = FALSE)

VIEWS <- list("Rule 1: FSC vs FSCW" = c(x = "FSCW", y = "FSC"),
              "Rule 2: SFL vs FSC" = c(x = "FSC", y = "SFL"),
              "WDF: SFL vs SSC" = c(x = "SSC", y = "SFL"))
ALL_PAIRS <- combn(SIGNALS, 2, simplify = FALSE)

# ---- comparison helpers ---------------------------------------------------------------

marginals <- function(m, source) {
  do.call(rbind, lapply(SIGNALS, function(s) {
    x <- m[, s]
    data.frame(source = source, signal = s, median = median(x), p01 = quantile(x, .01, names = FALSE),
               p99 = quantile(x, .99, names = FALSE), sd = sd(x),
               pct_at_0 = 100 * mean(x == 0), pct_at_255 = 100 * mean(x == 255))
  }))
}

# Shared mass of two normalised 2D histograms (1 = identical, 0 = no overlap). 32 x 32 bins.
hist_overlap <- function(a, b, x, y, bins = 32) {
  h <- function(m) {
    t <- table(factor(m[, x] %/% (256 / bins), 0:(bins - 1)), factor(m[, y] %/% (256 / bins), 0:(bins - 1)))
    t / sum(t)
  }
  sum(pmin(h(a), h(b)))
}

auc <- function(score, is_pos) {
  r <- rank(score)
  n1 <- sum(is_pos); n0 <- sum(!is_pos)
  (sum(r[is_pos]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

# kNN two-sample test: equal-size samples of A and B, half to train, half to test.
# Values get +/-0.5 jitter so integer ties don't decide neighbours.
knn_auc <- function(A, B, m, k = 25) {
  a <- A[sample(nrow(A), m), SIGNALS]; b <- B[sample(nrow(B), m), SIGNALS]
  X <- (rbind(a, b) + runif(2 * m * 4, -0.5, 0.5)) / 255
  lab <- factor(rep(c("A", "B"), each = m))
  tr <- c(sample(m, m %/% 2), m + sample(m, m %/% 2))
  te <- setdiff(seq_len(2 * m), tr)
  pred <- knn(X[tr, ], X[te, ], lab[tr], k = k, prob = TRUE)
  p_b <- ifelse(pred == "B", attr(pred, "prob"), 1 - attr(pred, "prob"))
  auc(p_b, lab[te] == "B")
}

# Naive reference generator: one 4D Gaussian with the file's overall mean and covariance, clipped.
naive_gaussian <- function(real, n) {
  z <- MASS::mvrnorm(n, colMeans(real), cov(real))
  z <- clip8(z)
  z <- z[z[, "FSC"] >= FSC_FLOOR, , drop = FALSE]
  colnames(z) <- SIGNALS
  z
}

density_panel <- function(m, x, y, title) {
  ggplot(as.data.frame(m), aes(.data[[x]], .data[[y]])) +
    geom_bin_2d(binwidth = c(2, 2), boundary = 0) +
    scale_fill_viridis_c(trans = "log10", name = "events") +
    coord_cartesian(xlim = c(-2, 257), ylim = c(-2, 257), expand = FALSE) +
    labs(title = title, x = x, y = y) +
    theme_bw(base_size = 8) +
    theme(legend.key.width = unit(2.5, "mm"), plot.title = element_text(size = 8))
}

marginal_panel <- function(real, syn, s) {
  d <- rbind(data.frame(v = real[, s], source = "real"), data.frame(v = syn[, s], source = "synthetic"))
  ggplot(d, aes(v, colour = source)) +
    geom_freqpoly(aes(y = after_stat(density)), binwidth = 2, boundary = 0, linewidth = 0.4) +
    scale_colour_manual(values = c(real = "black", synthetic = "red")) +
    coord_cartesian(xlim = c(0, 256)) +
    labs(title = s, x = NULL, y = "density", colour = NULL) +
    theme_bw(base_size = 8) + theme(legend.position = "bottom")
}

# ---- main loop ------------------------------------------------------------------------

marg_rows <- list(); score_rows <- list(); weight_rows <- list(); combined_rows <- list()
start_time <- as.POSIXct("2026-11-01 09:30:00", tz = "UTC")

for (i in seq_along(files)) {
  label <- sub("_ds1_events\\.csv$", "", basename(files[i]))
  real <- as.matrix(read.csv(files[i])[, SIGNALS])
  fit <- fit_populations(as.data.frame(real), dims = dims, seed = i)
  sim <- simulate_populations(fit, n = nrow(real), seed = 100 + i)
  syn <- sim$events

  keys <- xn_fake_keywords(sprintf("SY-%02d", i), start_time + 600 * i)
  write_xn_fcs(syn, keys, file.path(out_dir, "fcs", sprintf("synthetic.s%03d.fcs", i)))

  weight_rows[[i]] <- data.frame(label = label, population = names(fit$weights),
                                 pct_real_fit = round(100 * fit$weights, 2),
                                 pct_synthetic = round(100 * as.vector(table(factor(sub("^core", "", sim$pop),
                                   c("debris", "agg", "hfsat", seq_along(fit$clusters))))) / nrow(syn), 2))
  marg_rows[[i]] <- cbind(label = label, rbind(marginals(real, "real"), marginals(syn, "synthetic")))

  set.seed(1000 + i)
  m <- min(4000, nrow(real) %/% 2)
  half <- sample(nrow(real))
  naive <- naive_gaussian(real, nrow(real))
  sc <- data.frame(label = label, n_events = nrow(real), n_clusters = length(fit$clusters),
                   auc_real_vs_synth = knn_auc(real, syn, m),
                   auc_real_vs_real = knn_auc(real[half[1:m], ], real[half[(m + 1):(2 * m)], ], m),
                   auc_real_vs_naive = knn_auc(real, naive, m))
  for (s in SIGNALS) sc[[paste0("ks_", s)]] <- suppressWarnings(ks.test(real[, s], syn[, s])$statistic)
  for (pr in ALL_PAIRS) sc[[paste0("overlap_", pr[2], "_vs_", pr[1])]] <- hist_overlap(real, syn, pr[1], pr[2])
  for (pr in ALL_PAIRS) sc[[paste0("naive_overlap_", pr[2], "_vs_", pr[1])]] <- hist_overlap(real, naive, pr[1], pr[2])
  score_rows[[i]] <- sc
  cat(sprintf("  %s: %d events, %d core clusters | kNN AUC real-vs-synth %.3f (real-vs-real %.3f, naive %.3f)\n",
              label, nrow(real), length(fit$clusters), sc$auc_real_vs_synth, sc$auc_real_vs_real, sc$auc_real_vs_naive))

  # per-file figure: real row, synthetic row, marginal overlays
  rp <- lapply(names(VIEWS), function(v) density_panel(real, VIEWS[[v]][["x"]], VIEWS[[v]][["y"]], paste("REAL ·", v)))
  sp <- lapply(names(VIEWS), function(v) density_panel(syn, VIEWS[[v]][["x"]], VIEWS[[v]][["y"]], paste("SYNTHETIC ·", v)))
  mp <- lapply(SIGNALS, function(s) marginal_panel(real, syn, s))
  title <- sprintf("%s · real vs synthetic (core mixture on %s) · kNN AUC %.2f (real-vs-real %.2f, naive Gaussian %.2f)",
                   label, paste(dims, collapse = "/"), sc$auc_real_vs_synth, sc$auc_real_vs_real, sc$auc_real_vs_naive)
  g <- plot_grid(ggdraw() + draw_label(title, size = 10),
                 plot_grid(plotlist = rp, ncol = 3), plot_grid(plotlist = sp, ncol = 3),
                 plot_grid(plotlist = mp, ncol = 4), ncol = 1, rel_heights = c(0.05, 1, 1, 0.8))
  ggsave(file.path(out_dir, "figures", sprintf("%s_real_vs_synth.png", label)), g,
         width = 12, height = 10, dpi = 150, bg = "white")
  combined_rows[[label]] <- plot_grid(
    ggdraw() + draw_label(label, angle = 90, size = 9),
    plot_grid(rp[[2]], sp[[2]], rp[[3]], sp[[3]], ncol = 4), nrow = 1, rel_widths = c(0.03, 1))
}

ggsave(file.path(out_dir, "figures", "combined_real_vs_synth.png"),
       plot_grid(plotlist = combined_rows, ncol = 1), width = 15, height = 3.4 * length(combined_rows),
       dpi = 150, bg = "white")
write.csv(do.call(rbind, weight_rows), file.path(out_dir, "population_weights.csv"), row.names = FALSE)
write.csv(do.call(rbind, marg_rows), file.path(out_dir, "comparison_marginals.csv"), row.names = FALSE)
write.csv(do.call(rbind, score_rows), file.path(out_dir, "comparison_scores.csv"), row.names = FALSE)
cat("Done:", normalizePath(out_dir), "\n")
