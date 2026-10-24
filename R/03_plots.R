# 03 — Linear-scale plots with identical axis limits across files.
#
# Writes to figures/: <label>_pairs.png, <label>_key.png, <label>_hist.png,
#                     <label>_time.png (if a time/index parameter exists), combined_key_4x3.png

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
source(file.path(PROJECT_DIR, "R", "paths.R"))
source(file.path(PROJECT_DIR, "R", "helpers.R"))
if (!exists("cfg")) cfg <- get_config()
suppressPackageStartupMessages({
  library(ggplot2)
  library(cowplot)
})

cat("\n== 03 plots ==\n")
man <- read_out(cfg, "inputs_manifest.csv")
man <- man[man$is_fcs, ]
man$path <- file.path(cfg$input_dir, man$file)
pars <- read_out(cfg, "parameters.csv")
hdr <- read_out(cfg, "header_structure.csv")

N_BINS <- 128
# Key views as y-vs-x; SFL vs SSC is the standard WDF scattergram (x = SSC, y = SFL).
KEY_VIEWS <- list(
  "Rule 1: SFL vs FSCW" = c(x = "FSCW", y = "SFL"),
  "Rule 2: SFL vs FSC" = c(x = "FSC", y = "SFL"),
  "WDF: SFL vs SSC" = c(x = "SSC", y = "SFL")
)

# Collect every dataset as a data.frame with columns named by $PnN.
sets <- list()
for (i in seq_len(nrow(man))) {
  nd <- hdr$n_datasets_in_file[hdr$file == man$file[i]][1]
  for (n in seq_len(nd)) {
    ev <- load_events(man$path[i], n, nd, cfg)
    p <- pars[pars$file == man$file[i] & pars$dataset == n, ]
    df <- as.data.frame(ev$mat)
    names(df) <- p$PnN
    id <- if (nd > 1) sprintf("%s_ds%d", man$label[i], n) else man$label[i]
    pt <- PAPER_TABLE[PAPER_TABLE$label == man$label[i], ]
    title <- if (nrow(pt)) sprintf("%s · #%d %s · Rule1 %s Rule2 %s", id, pt$paper_sample,
                                   pt$diagnosis, pt$rule1, pt$rule2) else id
    sets[[id]] <- list(df = df, roles = setNames(p$role, p$PnN), title = title)
  }
}

# Shared limits per parameter name: 0 to the largest observed value in any file.
all_names <- unique(unlist(lapply(sets, function(s) names(s$df))))
lims <- sapply(all_names, function(nm) {
  mx <- max(unlist(lapply(sets, function(s) if (nm %in% names(s$df)) max(s$df[[nm]]) else NA)), na.rm = TRUE)
  mn <- min(0, unlist(lapply(sets, function(s) if (nm %in% names(s$df)) min(s$df[[nm]]) else NA)), na.rm = TRUE)
  c(mn, mx)
})
signal_names <- function(s) names(s$roles)[!s$roles %in% c("TIME", "INDEX")]
name_for_role <- function(s, role) {
  hit <- names(s$roles)[s$roles == role]
  if (length(hit) == 1) hit else NA_character_
}

density_plot <- function(df, x, y, title = NULL) {
  bw <- c(diff(lims[, x]), diff(lims[, y])) / N_BINS
  ggplot(df, aes(.data[[x]], .data[[y]])) +
    geom_bin_2d(binwidth = bw, boundary = 0) +
    scale_fill_viridis_c(trans = "log10", name = "events") +
    coord_cartesian(xlim = lims[, x] + c(-bw[1], bw[1]), ylim = lims[, y] + c(-bw[2], bw[2]),
                    expand = FALSE) +
    labs(title = title, x = paste(x, "(linear)"), y = paste(y, "(linear)")) +
    theme_bw(base_size = 9) +
    theme(legend.key.width = unit(3, "mm"), plot.title = element_text(size = 9))
}

save_png <- function(p, name, w, h) {
  ggsave(file.path(cfg$fig_dir, name), p, width = w, height = h, dpi = 150, bg = "white")
  cat("  wrote figures/", name, "\n", sep = "")
}

key_plots <- list()
for (id in names(sets)) {
  s <- sets[[id]]
  sig <- signal_names(s)

  # all pairwise density plots
  if (length(sig) >= 2) {
    prs <- combn(sig, 2, simplify = FALSE)
    pl <- lapply(prs, function(pr) density_plot(s$df, pr[1], pr[2]))
    nc <- min(3, length(pl))
    g <- plot_grid(ggdraw() + draw_label(s$title, size = 11),
                   plot_grid(plotlist = pl, ncol = nc), ncol = 1, rel_heights = c(0.06, 1))
    save_png(g, sprintf("%s_pairs.png", id), 4 * nc, 3.3 * ceiling(length(pl) / nc) + 0.4)
  }

  # key views
  kp <- lapply(names(KEY_VIEWS), function(v) {
    x <- name_for_role(s, KEY_VIEWS[[v]][["x"]])
    y <- name_for_role(s, KEY_VIEWS[[v]][["y"]])
    if (is.na(x) || is.na(y)) {
      warning(id, ": cannot draw '", v, "' — channel roles not found", call. = FALSE)
      return(ggdraw() + draw_label(paste(v, "\n(channel not identified)"), size = 9))
    }
    density_plot(s$df, x, y, v)
  })
  key_plots[[id]] <- kp
  g <- plot_grid(ggdraw() + draw_label(s$title, size = 11), plot_grid(plotlist = kp, ncol = 3),
                 ncol = 1, rel_heights = c(0.08, 1))
  save_png(g, sprintf("%s_key.png", id), 12, 3.8)

  # 1D histograms, linear, shared x-limits per parameter
  hp <- lapply(names(s$df), function(nm) {
    x <- s$df[[nm]]
    bw <- max(1, ceiling(diff(lims[, nm]) / 256))
    ggplot(data.frame(v = x), aes(v)) +
      geom_histogram(binwidth = bw, boundary = 0, fill = "grey30") +
      coord_cartesian(xlim = lims[, nm] + c(-bw, bw)) +
      labs(title = sprintf("%s (binwidth %g)", nm, bw), x = paste(nm, "(linear)"), y = "events") +
      theme_bw(base_size = 9)
  })
  g <- plot_grid(ggdraw() + draw_label(s$title, size = 11),
                 plot_grid(plotlist = hp, ncol = min(4, length(hp))), ncol = 1, rel_heights = c(0.08, 1))
  save_png(g, sprintf("%s_hist.png", id), 3.2 * min(4, length(hp)), 3 * ceiling(length(hp) / 4) + 0.4)

  # time / event-order parameter vs event index
  tnames <- names(s$roles)[s$roles %in% c("TIME", "INDEX")]
  if (length(tnames)) {
    tp <- lapply(tnames, function(nm) {
      ggplot(data.frame(i = seq_along(s$df[[nm]]), v = s$df[[nm]]), aes(i, v)) +
        geom_point(size = 0.2, alpha = 0.4) +
        labs(title = paste(nm, "vs event index"), x = "event index (file order)", y = nm) +
        theme_bw(base_size = 9)
    })
    save_png(plot_grid(plotlist = tp, ncol = 1), sprintf("%s_time.png", id), 6, 3 * length(tp))
  }
}

# Combined figure: files (rows) x the three key views (columns)
rows <- lapply(names(key_plots), function(id) {
  plot_grid(ggdraw() + draw_label(sets[[id]]$title, angle = 90, size = 9),
            plot_grid(plotlist = key_plots[[id]], ncol = 3), nrow = 1, rel_widths = c(0.05, 1))
})
g <- plot_grid(plotlist = rows, ncol = 1)
save_png(g, "combined_key_4x3.png", 12.5, 3.6 * length(rows))
