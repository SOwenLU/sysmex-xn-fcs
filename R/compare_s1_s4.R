# Compare S1 (#4, 88.7% malignant) with S4 (#18, 1.5% malignant): binned scattergrams on shared
# axes, coloured by % of each file's events so the 45k vs 4.9k event counts don't dominate,
# plus overlaid per-signal distributions.
#   Rscript R/compare_s1_s4.R [events_dir] [out_png]
# Defaults: <project>/outputs/events (written by run_all.R --export-events) and
# <project>/outputs/figures/compare_S1_S4.png.
suppressPackageStartupMessages({ library(ggplot2); library(cowplot) })

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
args <- commandArgs(trailingOnly = TRUE)
ev_dir <- if (length(args) >= 1) args[1] else file.path(PROJECT_DIR, "outputs", "events")
out_png <- if (length(args) >= 2) args[2] else file.path(PROJECT_DIR, "outputs", "figures", "compare_S1_S4.png")

lab <- c(S1 = "S1 · #4 adenocarcinoma · 88.7% malignant",
         S4 = "S4 · #18 adenocarcinoma · 1.5% malignant")
ev <- do.call(rbind, lapply(names(lab), function(s) {
  d <- read.csv(file.path(ev_dir, sprintf("%s_ds1_events.csv", s)))
  d$file <- s
  d
}))
ev$file <- factor(ev$file, levels = names(lab))
cat("Events:", paste(names(table(ev$file)), table(ev$file), collapse = ", "), "\n")

INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e6e5e1"
SERIES <- c(S1 = "#2a78d6", S4 = "#eb6834")
SEQ <- c("#cde2fb", "#86b6ef", "#3987e5", "#1c5cab", "#0d366b")

base_theme <- theme_minimal(base_size = 10) +
  theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA),
        panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
        axis.text = element_text(colour = MUTED), axis.title = element_text(colour = INK2),
        strip.text = element_text(colour = INK, face = "bold", hjust = 0),
        plot.title = element_text(colour = INK, face = "bold"))

VIEWS <- list(c("SSC", "SFL", "WDF scattergram"),
              c("FSC", "SFL", "Rule 2 view"),
              c("FSCW", "FSC", "Rule 1 view"))
BIN <- 4

scatter_row <- function(v) {
  d <- data.frame(x = ev[[v[1]]] %/% BIN * BIN, y = ev[[v[2]]] %/% BIN * BIN, file = ev$file)
  b <- aggregate(list(n = rep(1, nrow(d))), d, length)
  b$pct <- 100 * b$n / as.numeric(table(ev$file)[as.character(b$file)])
  ggplot(b, aes(x, y, fill = pct)) +
    geom_tile(width = BIN, height = BIN) +
    facet_wrap(~file, labeller = labeller(file = lab)) +
    scale_fill_gradientn(colours = SEQ, trans = "log10", name = "% of\nevents",
                         breaks = c(0.01, 0.1, 1), labels = c("0.01", "0.1", "1")) +
    coord_fixed(xlim = c(0, 256), ylim = c(0, 256), expand = FALSE) +
    labs(x = v[1], y = v[2], title = v[3]) + base_theme
}

long <- do.call(rbind, lapply(c("SSC", "SFL", "FSC", "FSCW"), function(s)
  data.frame(signal = s, value = ev[[s]], file = ev$file)))
long$signal <- factor(long$signal, levels = c("SSC", "SFL", "FSC", "FSCW"))
hist_row <- ggplot(long, aes(value, colour = file)) +
  geom_freqpoly(aes(y = after_stat(density)), binwidth = 4, linewidth = 0.7) +
  facet_wrap(~signal, nrow = 1, scales = "free_y") +
  scale_colour_manual(values = SERIES, labels = c(S1 = "S1 (#4)", S4 = "S4 (#18)"), name = NULL) +
  scale_x_continuous(limits = c(0, 256), breaks = c(0, 128, 255)) +
  labs(x = "channel value (0–255)", y = "density", title = "Per-signal distributions") +
  base_theme + theme(legend.position = "top", legend.justification = "left",
                     axis.text.y = element_blank())

p <- plot_grid(scatter_row(VIEWS[[1]]), scatter_row(VIEWS[[2]]), scatter_row(VIEWS[[3]]),
               hist_row, ncol = 1, rel_heights = c(1, 1, 1, 0.75))
ggsave(out_png, p, width = 8, height = 15.5, dpi = 130, bg = "#fcfcfb")
cat("Wrote", out_png, "\n")
