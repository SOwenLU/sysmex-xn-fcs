# Overlay candidate WDF populations (red outlines) on the same density plots as 03_plots.R,
# for a quick human check of the suggested population labels. Never touches figures/.
#
#   Rscript R/annotate_candidate_populations.R <events_folder> <out_folder> [dims]
#
# <events_folder> holds the per-event CSVs from run_all.R --export-events.
# [dims] are the signals the mixture is fitted on, comma-separated (default SSC,SFL,FSC,FSCW).
# Populations: three rule-based classes first (debris SFL < 16; aggregates FSC = 255, the paper's
# Area 1; HF saturated SFL = 255), then a Gaussian mixture on the remaining unsaturated events,
# with each cluster named by rule from its medians. Names are suggestions, not validated gates.

suppressPackageStartupMessages({
  library(mclust)
  library(ggplot2)
  library(cowplot)
})

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% 2:3) stop("usage: Rscript R/annotate_candidate_populations.R <events_folder> <out_folder> [dims]")
ev_dir <- normalizePath(args[1], mustWork = TRUE)
out_dir <- args[2]
if (normalizePath(out_dir, mustWork = FALSE) == normalizePath(file.path(ev_dir, "..", "figures"), mustWork = FALSE)) {
  stop("refusing to write into the original figures/ folder", call. = FALSE)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

N_BINS <- 128
LIM <- c(0, 255)
SIGNALS <- c("SSC", "SFL", "FSC", "FSCW")
FIT_DIMS <- if (length(args) == 3) strsplit(args[3], ",", fixed = TRUE)[[1]] else SIGNALS
stopifnot(all(FIT_DIMS %in% SIGNALS), length(FIT_DIMS) >= 2)
KEY_VIEWS <- list(
  "Rule 1 (paper axes): FSC vs FSCW" = c(x = "FSCW", y = "FSC"),
  "Rule 2: SFL vs FSC" = c(x = "FSC", y = "SFL"),
  "WDF: SFL vs SSC" = c(x = "SSC", y = "SFL")
)
PAPER <- data.frame(label = c("S1", "S2", "S3", "S4"), sample = c(4, 13, 16, 18),
                    diagnosis = c("adenocarcinoma", "adenocarcinoma", "mesothelioma", "adenocarcinoma"),
                    rule1 = c("+", "+", "-", "-"), rule2 = c("+", "-", "+", "-"))
SHORT <- c("Lymphocytes" = "LY", "Neutrophil-like" = "NE?", "Mono/macrophage band" = "MO",
           "High-SFL cells" = "HiSFL", "Large cells (high FSC)" = "LG",
           "Small low-FSC events" = "SM", "Unassigned" = "?")
ELLIPSE_P <- 0.8   # each outline encloses ~80% of its cluster if it were Gaussian

# Rule-based name from a cluster's medians (8-bit units); thresholds read off the mixture fits.
name_cluster <- function(m) {
  if (m["FSC"] < 35) return("Small low-FSC events")
  if (m["SSC"] < 95 && m["SFL"] < 80) return("Lymphocytes")
  if (m["SSC"] > 110 && m["SFL"] < 65) return("Neutrophil-like")
  if (m["FSC"] >= 100) return("Large cells (high FSC)")
  if (m["SFL"] >= 170) return("High-SFL cells")
  if (m["SFL"] >= 100) return("Mono/macrophage band")
  "Unassigned"
}

ellipse_xy <- function(mu, S, p = ELLIPSE_P, n = 100) {
  r <- sqrt(qchisq(p, 2))
  e <- eigen(S, symmetric = TRUE)
  t <- seq(0, 2 * pi, length.out = n)
  pts <- t(mu + e$vectors %*% diag(sqrt(pmax(e$values, 1e-6))) %*% rbind(r * cos(t), r * sin(t)))
  data.frame(x = pts[, 1], y = pts[, 2])
}

files <- sort(list.files(ev_dir, pattern = "^S[0-9]+_ds[0-9]+_events\\.csv$", full.names = TRUE))
if (!length(files)) stop("no <label>_ds<n>_events.csv files in ", ev_dir, call. = FALSE)

density_plot <- function(df, x, y, title, pops, n_total) {
  bw <- diff(LIM) / N_BINS
  p <- ggplot(df, aes(.data[[x]], .data[[y]])) +
    geom_bin_2d(binwidth = c(bw, bw), boundary = 0) +
    scale_fill_viridis_c(trans = "log10", name = "events")
  # Rule-based classes as dashed bands on whichever axis defines them
  band <- function(p, axis, lo, hi, label, at_low) {
    if (!axis %in% c(x, y)) return(p)
    pos <- if (at_low) hi + 5 else lo - 5
    if (axis == y) {
      p + annotate("rect", xmin = LIM[1], xmax = LIM[2], ymin = lo, ymax = hi,
                   colour = "red", fill = NA, linetype = "dashed", linewidth = 0.4) +
        annotate("text", x = LIM[2] - 2, y = pos, label = label, colour = "red", hjust = 1,
                 vjust = if (at_low) 0 else 1, size = 2.6, fontface = "bold")
    } else {
      p + annotate("rect", ymin = LIM[1], ymax = LIM[2], xmin = lo, xmax = hi,
                   colour = "red", fill = NA, linetype = "dashed", linewidth = 0.4) +
        annotate("text", y = LIM[2] - 2, x = pos, label = label, colour = "red", angle = 90,
                 hjust = 1, vjust = if (at_low) 1 else 0, size = 2.6, fontface = "bold")
    }
  }
  p <- band(p, "SFL", -1, 15.5, sprintf("DEB %.0f%%", pops$deb_pct), TRUE)
  p <- band(p, "SFL", 251, 257, sprintf("HFSAT %.0f%%", pops$hfsat_pct), FALSE)
  p <- band(p, "FSC", 251, 257, sprintf("AGG %.0f%%", pops$agg_pct), FALSE)
  for (k in seq_along(pops$clusters)) {
    cl <- pops$clusters[[k]]
    el <- ellipse_xy(cl$mean[c(x, y)], cl$cov[c(x, y), c(x, y)])
    top <- el[which.max(el$y), ]  # label at the ellipse's top so nearby clusters don't collide
    p <- p + geom_path(data = el, aes(x, y), inherit.aes = FALSE, colour = "red", linewidth = 0.5) +
      annotate("label", x = min(max(top$x, 12), 243), y = min(top$y, 240),
               label = sprintf("%s %.0f%%", SHORT[[cl$name]], cl$pct),
               colour = "red", fill = alpha("white", 0.75), size = 2.4, fontface = "bold",
               label.padding = unit(0.6, "mm"))
  }
  p + coord_cartesian(xlim = LIM + c(-bw, bw), ylim = LIM + c(-bw, bw), expand = FALSE) +
    labs(title = title, x = paste(x, "(linear)"), y = paste(y, "(linear)")) +
    theme_bw(base_size = 9) +
    theme(legend.key.width = unit(3, "mm"), plot.title = element_text(size = 9))
}

save_png <- function(p, name, w, h) {
  ggsave(file.path(out_dir, name), p, width = w, height = h, dpi = 150, bg = "white")
  cat("  wrote", name, "\n")
}

legend_txt <- paste0(
  "Red = SUGGESTED populations (Gaussian mixture on ", paste(FIT_DIMS, collapse = "/"),
  "; ellipses enclose ~80%; % of all events). Labels need human review.\n",
  "LY lymphocytes · NE? neutrophil-like · MO mono/macrophage band · HiSFL high-SFL cells · ",
  "LG large high-FSC cells · SM small low-FSC events · ? unassigned ·\nDEB debris (SFL<16) · AGG aggregates (FSC = 255, paper Area 1) · HFSAT SFL = 255, FSC < 255.")

set.seed(1)
summary_rows <- list()
key_plots <- list()
for (f in files) {
  id <- sub("_ds1$", "", sub("_events\\.csv$", "", basename(f)))
  df <- read.csv(f)[, SIGNALS]
  n <- nrow(df)
  deb <- df$SFL < 16
  agg <- !deb & df$FSC == 255
  hfsat <- !deb & !agg & df$SFL == 255
  sat <- df$SFL == 255 | df$SSC == 255 | df$FSC == 255
  core <- df[!deb & !sat, ]
  fit_rows <- sample(nrow(core), min(8000, nrow(core)))
  m <- Mclust(core[fit_rows, FIT_DIMS], G = 3:7, modelNames = "VVV", verbose = FALSE)
  cl <- predict(m, core[, FIT_DIMS])$classification
  cat(sprintf("  %s: %d clusters on %s; debris %.1f%%, AGG %.1f%%, HFSAT %.1f%%, SSC-only saturated %.1f%%\n",
              id, m$G, paste(FIT_DIMS, collapse = ","), 100 * mean(deb), 100 * mean(agg),
              100 * mean(hfsat), 100 * mean(sat & !deb & !agg & !hfsat)))

  clusters <- lapply(sort(unique(cl)), function(k) {
    x <- as.matrix(core[cl == k, SIGNALS])
    med <- apply(x, 2, median)
    list(id = k, name = name_cluster(med), pct = 100 * nrow(x) / n,
         mean = colMeans(x), cov = cov(x), med = med,
         p10 = apply(x, 2, quantile, 0.1), p90 = apply(x, 2, quantile, 0.9))
  })
  pops <- list(clusters = clusters, deb_pct = 100 * mean(deb), agg_pct = 100 * mean(agg),
               hfsat_pct = 100 * mean(hfsat))
  for (c in clusters) {
    summary_rows[[length(summary_rows) + 1]] <- data.frame(
      label = id, fit_dims = paste(FIT_DIMS, collapse = ","), cluster = c$id, population = c$name, pct_of_events = round(c$pct, 1),
      t(setNames(round(c$med), paste0(SIGNALS, "_median"))),
      t(setNames(round(c$p10), paste0(SIGNALS, "_p10"))),
      t(setNames(round(c$p90), paste0(SIGNALS, "_p90"))))
  }

  pt <- PAPER[PAPER$label == id, ]
  title <- if (nrow(pt)) sprintf("%s · #%d %s · Rule1 %s Rule2 %s · SUGGESTED populations",
                                 id, pt$sample, pt$diagnosis, pt$rule1, pt$rule2) else id
  kp <- lapply(names(KEY_VIEWS), function(v) density_plot(df, KEY_VIEWS[[v]][["x"]], KEY_VIEWS[[v]][["y"]], v, pops, n))
  key_plots[[id]] <- kp
  g <- plot_grid(ggdraw() + draw_label(title, size = 11), plot_grid(plotlist = kp, ncol = 3),
                 ggdraw() + draw_label(legend_txt, size = 7), ncol = 1, rel_heights = c(0.08, 1, 0.1))
  save_png(g, sprintf("%s_key_annotated.png", id), 12, 4.1)

  prs <- combn(SIGNALS, 2, simplify = FALSE)
  pl <- lapply(prs, function(pr) density_plot(df, pr[1], pr[2], NULL, pops, n))
  g <- plot_grid(ggdraw() + draw_label(title, size = 11), plot_grid(plotlist = pl, ncol = 3),
                 ggdraw() + draw_label(legend_txt, size = 7), ncol = 1, rel_heights = c(0.06, 1, 0.06))
  save_png(g, sprintf("%s_pairs_annotated.png", id), 12, 7.4)
}

rows <- lapply(names(key_plots), function(id) {
  plot_grid(ggdraw() + draw_label(id, angle = 90, size = 9),
            plot_grid(plotlist = key_plots[[id]], ncol = 3), nrow = 1, rel_widths = c(0.03, 1))
})
g <- plot_grid(plot_grid(plotlist = rows, ncol = 1), ggdraw() + draw_label(legend_txt, size = 8),
               ncol = 1, rel_heights = c(1, 0.02))
save_png(g, "combined_key_4x3_annotated.png", 12.5, 3.6 * length(rows) + 0.4)

write.csv(do.call(rbind, summary_rows), file.path(out_dir, "candidate_populations.csv"), row.names = FALSE)
cat("  wrote candidate_populations.csv\n")
