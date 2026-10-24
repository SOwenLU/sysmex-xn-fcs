# Overlay the healthy-PE population table (config/healthy_pe_populations.csv) on the S4 and S1
# scattergrams: each population drawn as a centre ± 2 SD ellipse with a direct label.
#
#   Rscript R/plot_reference_populations.R [events_dir] [out_png]
# Defaults: <project>/outputs/events and <project>/outputs/reference_populations/populations_overlay.png.
suppressPackageStartupMessages({ library(ggplot2); library(cowplot) })

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
args <- commandArgs(trailingOnly = TRUE)
ev_dir <- if (length(args) >= 1) args[1] else file.path(PROJECT_DIR, "outputs", "events")
out_png <- if (length(args) >= 2) args[2] else
  file.path(PROJECT_DIR, "outputs", "reference_populations", "populations_overlay.png")
dir.create(dirname(out_png), recursive = TRUE, showWarnings = FALSE)

pops <- read.csv(file.path(PROJECT_DIR, "config", "healthy_pe_populations.csv"))
lab <- c(S4 = "S4 · #18 · 1.5% malignant", S1 = "S1 · #4 · 88.7% malignant")
ev <- do.call(rbind, lapply(names(lab), function(s) {
  d <- read.csv(file.path(ev_dir, sprintf("%s_ds1_events.csv", s)))
  d$file <- s
  d
}))
ev$file <- factor(ev$file, levels = names(lab))

INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e6e5e1"
SEQ <- c("#e6e5e1", "#b7d3f6", "#86b6ef", "#3987e5", "#1c5cab")
ASSUMED <- "#eb6834"
BIN <- 4

# Centre ± k SD ellipse of a bivariate normal with correlation r.
ellipse <- function(cx, sx, cy, sy, r = 0, k = 2) {
  t <- seq(0, 2 * pi, length.out = 80)
  data.frame(x = pmin(pmax(cx + k * sx * cos(t), 0), 255),
             y = pmin(pmax(cy + k * sy * (r * cos(t) + sqrt(1 - r^2) * sin(t)), 0), 255))
}
pair_r <- function(p, a, b) {
  nm <- intersect(c(paste0("r_", a, "_", b), paste0("r_", b, "_", a)), names(p))
  if (length(nm)) p[[nm[1]]] else 0
}

view <- function(xv, yv, title) {
  d <- data.frame(x = ev[[xv]] %/% BIN * BIN, y = ev[[yv]] %/% BIN * BIN, file = ev$file)
  b <- aggregate(list(n = rep(1, nrow(d))), d, length)
  b$pct <- 100 * b$n / as.numeric(table(ev$file)[as.character(b$file)])
  el <- do.call(rbind, lapply(seq_len(nrow(pops)), function(i) {
    p <- pops[i, ]
    e <- ellipse(p[[paste0(xv, "_centre")]], p[[paste0(xv, "_sd")]], p[[paste0(yv, "_centre")]], p[[paste0(yv, "_sd")]],
                 pair_r(p, xv, yv))
    e$population <- p$population
    e$assumed <- grepl("positions ASSUMED", p$status)
    e
  }))
  cen <- data.frame(population = pops$population, x = pmin(pops[[paste0(xv, "_centre")]], 250),
                    y = pmin(pops[[paste0(yv, "_centre")]], 250),
                    assumed = grepl("positions ASSUMED", pops$status))
  # HF-BF macrophages and mesothelial cells share a region: one label for both.
  cen$population[cen$population == "hfbf_macrophage"] <- "HF-BF (macrophage + mesothelial)"
  cen <- cen[cen$population != "mesothelial", ]
  # Labels near the top or right edge go below / left of their point so they stay on the plot.
  cen$lx <- pmin(cen$x, 200)
  cen$vj <- ifelse(cen$y >= 240, 1.6, -0.6)
  # Neighbours that would collide: one of each pair goes below its point (aggregate a line lower).
  below <- cen$population %in% c("eosinophil", "monocyte")
  cen$vj[below] <- 1.6
  cen$vj[cen$population == "aggregate"] <- 3.2
  ggplot() +
    geom_tile(data = b, aes(x, y, fill = pct), width = BIN, height = BIN) +
    geom_path(data = el, aes(x, y, group = population, colour = assumed, linetype = assumed), linewidth = 0.6) +
    geom_point(data = cen, aes(x, y, colour = assumed), size = 1.6) +
    geom_label(data = cen, aes(lx, y, label = population, colour = assumed, vjust = vj), size = 2.6,
               linewidth = 0, label.padding = unit(0.08, "lines"), fill = "#fcfcfbcc") +
    facet_wrap(~file, labeller = labeller(file = lab)) +
    scale_fill_gradientn(colours = SEQ, trans = "log10", name = "% of\nevents",
                         breaks = c(0.01, 0.1, 1), labels = c("0.01", "0.1", "1")) +
    scale_colour_manual(values = c(`FALSE` = INK, `TRUE` = ASSUMED), guide = "none") +
    scale_linetype_manual(values = c(`FALSE` = "solid", `TRUE` = "dashed"), guide = "none") +
    coord_fixed(xlim = c(0, 256), ylim = c(0, 256), expand = FALSE) +
    labs(x = xv, y = yv, title = title) +
    theme_minimal(base_size = 10) +
    theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA),
          panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
          axis.text = element_text(colour = MUTED), axis.title = element_text(colour = INK2),
          strip.text = element_text(colour = INK, face = "bold", hjust = 0),
          plot.title = element_text(colour = INK, face = "bold"))
}

note <- ggdraw() + draw_label(
  paste0("Ellipses: centre ± 2 SD from config/healthy_pe_populations.csv. Solid black = measured from S1–S4 gates; ",
         "dashed orange = assumed (eosinophils).\nSFL ≥ ~214 is the calibrated HF-BF cutoff; centres above 255 ",
         "are latent and get clipped at 255."),
  size = 8, colour = INK2, x = 0.01, hjust = 0)
p <- plot_grid(view("SSC", "SFL", "WDF scattergram (SFL vs SSC)"),
               view("FSC", "SFL", "Size view (SFL vs FSC)"), note,
               ncol = 1, rel_heights = c(1, 1, 0.08))
ggsave(out_png, p, width = 9, height = 9.6, dpi = 140, bg = "#fcfcfb")
cat("Wrote", out_png, "\n")
