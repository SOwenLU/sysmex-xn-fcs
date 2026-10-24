# One synthetic healthy pleural-effusion file from config/healthy_pe_populations.csv, plotted
# next to S4 on the same views as compare_S1_S4.png. A visual sanity check of the suggested values,
# not the generator: each population is one multivariate normal (centres, SDs, correlations from the
# config) and there is no sample-to-sample variation.
#
#   Rscript R/simulate_healthy_test.R [events_dir] [out_png] [n_events] [seed]
# Defaults: <project>/outputs/events, <project>/outputs/reference_populations/synthetic_test.png,
# 12000 events (≈ 12 × the benign median TNC of ~1000/µL), seed 1.
suppressPackageStartupMessages({ library(ggplot2); library(cowplot) })

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
args <- commandArgs(trailingOnly = TRUE)
ev_dir <- if (length(args) >= 1) args[1] else file.path(PROJECT_DIR, "outputs", "events")
out_png <- if (length(args) >= 2) args[2] else
  file.path(PROJECT_DIR, "outputs", "reference_populations", "synthetic_test.png")
n_events <- if (length(args) >= 3) as.integer(args[3]) else 12000L
seed <- if (length(args) >= 4) as.integer(args[4]) else 1L
set.seed(seed)

SIGNALS <- c("SSC", "SFL", "FSC", "FSCW")
DEBRIS_PCT <- 8  # % of all events (config debris row)
pops <- read.csv(file.path(PROJECT_DIR, "config", "healthy_pe_populations.csv"))
cells <- pops[pops$population != "debris", ]
deb <- pops[pops$population == "debris", ]

n_deb <- round(n_events * DEBRIS_PCT / 100)
n_cell <- as.vector(rmultinom(1, n_events - n_deb, cells$pct_cells / sum(cells$pct_cells)))

clip <- function(x) pmin(pmax(round(x), 0), 255)
# Multivariate normal per population from the config's centres, SDs and pairwise correlations.
draw <- function(p, n) {
  R <- diag(4)
  dimnames(R) <- list(SIGNALS, SIGNALS)
  for (pr in combn(SIGNALS, 2, simplify = FALSE)) R[pr[1], pr[2]] <- R[pr[2], pr[1]] <- p[[paste0("r_", pr[1], "_", pr[2])]]
  sdv <- unlist(p[paste0(SIGNALS, "_sd")])
  S <- diag(sdv) %*% R %*% diag(sdv)
  ev <- eigen(S, symmetric = TRUE)  # nudge to positive semi-definite if the pairwise rs disagree
  S <- ev$vectors %*% diag(pmax(ev$values, 0)) %*% t(ev$vectors)
  z <- matrix(rnorm(n * 4), n) %*% t(ev$vectors %*% diag(sqrt(pmax(ev$values, 0))))
  d <- sweep(z, 2, unlist(p[paste0(SIGNALS, "_centre")]), "+")
  d <- as.data.frame(apply(d, 2, clip))
  names(d) <- SIGNALS
  d$FSC <- pmax(d$FSC, 10)  # instrument FSC floor seen in S1–S4
  d$population <- rep(p$population, n)
  d
}
syn <- do.call(rbind, c(lapply(seq_len(nrow(cells)), function(i) draw(cells[i, ], n_cell[i])),
                        list(draw(deb, n_deb))))
# Debris SFL is zero-inflated: about half at 0, the rest a decaying tail below 16.
nd <- sum(syn$population == "debris")
syn$SFL[syn$population == "debris"] <- ifelse(runif(nd) < 0.5, 0, pmin(rgeom(nd, 0.25) + 1, 15))
cat("Synthetic events:", nrow(syn), "\n")
print(round(100 * prop.table(table(syn$population)), 1))

s4 <- read.csv(file.path(ev_dir, "S4_ds1_events.csv"))[, SIGNALS]
both <- rbind(cbind(s4, file = "S4"), cbind(syn[, SIGNALS], file = "synthetic"))
lab <- c(S4 = sprintf("S4 · #18 · real, %d events", nrow(s4)),
         synthetic = sprintf("Synthetic healthy PE · %d events · seed %d", nrow(syn), seed))
both$file <- factor(both$file, levels = names(lab))

INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e6e5e1"
SEQ <- c("#cde2fb", "#86b6ef", "#3987e5", "#1c5cab", "#0d366b")
BIN <- 4
view <- function(xv, yv, title) {
  d <- data.frame(x = both[[xv]] %/% BIN * BIN, y = both[[yv]] %/% BIN * BIN, file = both$file)
  b <- aggregate(list(n = rep(1, nrow(d))), d, length)
  b$pct <- 100 * b$n / as.numeric(table(both$file)[as.character(b$file)])
  ggplot(b, aes(x, y, fill = pct)) +
    geom_tile(width = BIN, height = BIN) +
    facet_wrap(~file, labeller = labeller(file = lab)) +
    scale_fill_gradientn(colours = SEQ, trans = "log10", name = "% of\nevents",
                         breaks = c(0.01, 0.1, 1), labels = c("0.01", "0.1", "1")) +
    coord_fixed(xlim = c(0, 256), ylim = c(0, 256), expand = FALSE) +
    labs(x = xv, y = yv, title = title) +
    theme_minimal(base_size = 10) +
    theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA),
          panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
          axis.text = element_text(colour = MUTED), axis.title = element_text(colour = INK2),
          strip.text = element_text(colour = INK, face = "bold", hjust = 0),
          plot.title = element_text(colour = INK, face = "bold"))
}
p <- plot_grid(view("SSC", "SFL", "WDF scattergram (SFL vs SSC)"),
               view("FSC", "SFL", "Size view (SFL vs FSC)"),
               view("FSCW", "FSC", "Rule 1 view (FSC vs FSCW)"), ncol = 1)
ggsave(out_png, p, width = 8, height = 12, dpi = 130, bg = "#fcfcfb")
cat("Wrote", out_png, "\n")
