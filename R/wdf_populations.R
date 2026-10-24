# WDF population model: fit per-population parameters to one file's events, and simulate events
# from them. Sourced by synth_compare.R.
#
# Populations (8-bit linear values, columns SSC, SFL, FSC, FSCW):
#   debris  SFL < 16. SFL is zero-inflated with a truncated geometric tail; the rest is a
#           Gaussian on log1p scale.
#   agg     FSC = 255 (the paper's Area 1). FSC is fixed at 255; SSC/SFL/FSCW come from a latent
#           Gaussian whose marginals are fitted with censoring at 0 and 255, so pile-ups at 255
#           come from clipping rather than being copied.
#   hfsat   SFL = 255 and FSC < 255. SFL is fixed at 255; the rest is handled as in agg, with FSC
#           truncated below 255.
#   core    everything else: a Gaussian mixture fitted on `dims`, then each cluster is described by
#           its 4-signal mean and covariance and simulated as a truncated Gaussian.

suppressPackageStartupMessages(library(mclust))

SIGNALS <- c("SSC", "SFL", "FSC", "FSCW")
FSC_FLOOR <- 10
TOP <- 255

classify_events <- function(df) {
  deb <- df$SFL < 16
  agg <- !deb & df$FSC == TOP
  hfsat <- !deb & !agg & df$SFL == TOP
  other_sat <- !deb & !agg & !hfsat & (df$SSC == TOP | df$FSCW == TOP)
  cls <- ifelse(deb, "debris", ifelse(agg, "agg", ifelse(hfsat | other_sat, "hfsat", "core")))
  factor(cls, levels = c("debris", "agg", "hfsat", "core"))
}

# Normal fitted to integer values censored at 0 and 255 (values sit on bins of width 1).
fit_censored_normal <- function(x) {
  lo <- x <= 0
  hi <- x >= TOP
  mid <- x[!lo & !hi]
  start <- c(mean(x), log(max(sd(x), 1)))
  nll <- function(p) {
    mu <- p[1]; s <- exp(p[2])
    -(sum(dnorm(mid, mu, s, log = TRUE)) +
        sum(lo) * pnorm(0.5, mu, s, log.p = TRUE) +
        sum(hi) * pnorm(TOP - 0.5, mu, s, lower.tail = FALSE, log.p = TRUE))
  }
  o <- optim(start, nll, method = "L-BFGS-B", lower = c(-200, log(0.5)), upper = c(800, log(400)))
  c(mean = o$par[1], sd = exp(o$par[2]))
}

# Latent Gaussian for partly censored columns: censored-normal marginals plus a Spearman-based
# correlation (Pearson ~ 2 sin(pi r / 6)).
fit_latent <- function(x) {
  x <- as.matrix(x)
  marg <- t(apply(x, 2, fit_censored_normal))
  r <- suppressWarnings(cor(x, method = "spearman"))
  r[is.na(r)] <- 0
  diag(r) <- 1
  R <- 2 * sin(pi * r / 6)
  ev <- eigen(R, symmetric = TRUE)  # nudge to positive definite if needed
  R <- ev$vectors %*% diag(pmax(ev$values, 1e-4)) %*% t(ev$vectors)
  R <- cov2cor(R)
  list(mean = marg[, "mean"], cov = diag(marg[, "sd"]) %*% R %*% diag(marg[, "sd"]),
       cols = colnames(x))
}

fit_populations <- function(df, dims = c("SSC", "SFL", "FSC"), seed = 1, max_fit = 8000) {
  set.seed(seed)
  df <- df[, SIGNALS]
  cls <- classify_events(df)
  n <- nrow(df)

  d <- df[cls == "debris", ]
  sfl_nz <- d$SFL[d$SFL > 0]
  # truncated geometric on 1..15: solve for the decay rate that matches the observed mean
  geo_mean <- function(l) { k <- 1:15; sum(k * exp(-l * k)) / sum(exp(-l * k)) }
  lam <- if (length(sfl_nz) > 1 && mean(sfl_nz) < 8) uniroot(function(l) geo_mean(l) - mean(sfl_nz), c(1e-4, 10))$root else 1e-4
  debris <- list(p0 = mean(d$SFL == 0), lambda = lam,
                 mean = colMeans(log1p(d[, c("SSC", "FSC", "FSCW")])),
                 cov = cov(log1p(d[, c("SSC", "FSC", "FSCW")])))

  agg <- if (sum(cls == "agg") >= 10) fit_latent(df[cls == "agg", c("SSC", "SFL", "FSCW")]) else NULL
  hfsat <- if (sum(cls == "hfsat") >= 10) fit_latent(df[cls == "hfsat", c("SSC", "FSC", "FSCW")]) else NULL

  core <- df[cls == "core", ]
  fit_rows <- sample(nrow(core), min(max_fit, nrow(core)))
  m <- Mclust(core[fit_rows, dims], G = 3:7, modelNames = "VVV", verbose = FALSE)
  cl <- predict(m, core[, dims])$classification
  clusters <- lapply(sort(unique(cl)), function(k) {
    x <- as.matrix(core[cl == k, SIGNALS])
    list(weight = nrow(x) / n, mean = colMeans(x), cov = cov(x), median = apply(x, 2, median))
  })

  list(n = n, dims = dims,
       weights = c(debris = mean(cls == "debris"), agg = mean(cls == "agg"),
                   hfsat = mean(cls == "hfsat"), sapply(clusters, `[[`, "weight")),
       debris = debris, agg = agg, hfsat = hfsat, clusters = clusters)
}

# Draw n rows from N(mean, cov) that satisfy keep(); rejection sampling in batches.
rmvn_keep <- function(n, mean, cov, keep, max_rounds = 200) {
  if (n == 0) return(matrix(numeric(), 0, length(mean), dimnames = list(NULL, names(mean))))
  out <- NULL
  L <- chol(cov + diag(1e-6, length(mean)))
  for (i in seq_len(max_rounds)) {
    z <- matrix(rnorm(2 * n * length(mean)), ncol = length(mean)) %*% L
    z <- sweep(z, 2, mean, "+")
    colnames(z) <- names(mean)
    out <- rbind(out, z[keep(z), , drop = FALSE])
    if (nrow(out) >= n) return(out[seq_len(n), , drop = FALSE])
  }
  stop("rejection sampling accepted too few draws (", nrow(out), " of ", n, ")", call. = FALSE)
}

clip8 <- function(x) pmin(pmax(round(x), 0), TOP)

simulate_populations <- function(fit, n = fit$n, seed = 1) {
  set.seed(seed)
  counts <- as.vector(rmultinom(1, n, fit$weights))
  names(counts) <- names(fit$weights)
  parts <- list()

  # debris
  k <- counts["debris"]
  if (k > 0) {
    lg <- rmvn_keep(k, fit$debris$mean, fit$debris$cov,
                    function(z) round(expm1(z[, "FSC"])) >= FSC_FLOOR)
    tail <- sample(1:15, k, replace = TRUE, prob = exp(-fit$debris$lambda * (1:15)))
    sfl <- ifelse(runif(k) < fit$debris$p0, 0, tail)
    parts$debris <- cbind(SSC = clip8(expm1(lg[, "SSC"])), SFL = sfl,
                          FSC = clip8(expm1(lg[, "FSC"])), FSCW = clip8(expm1(lg[, "FSCW"])))
  }
  # aggregates: FSC fixed at 255, the rest latent then clipped
  k <- counts["agg"]
  if (k > 0 && !is.null(fit$agg)) {
    z <- rmvn_keep(k, setNames(fit$agg$mean, fit$agg$cols), fit$agg$cov,
                   function(z) round(z[, "SFL"]) >= 16)
    parts$agg <- cbind(SSC = clip8(z[, "SSC"]), SFL = clip8(z[, "SFL"]), FSC = TOP, FSCW = clip8(z[, "FSCW"]))
  }
  # high-fluorescence saturated: SFL fixed at 255, FSC kept in [floor, 254]
  k <- counts["hfsat"]
  if (k > 0 && !is.null(fit$hfsat)) {
    z <- rmvn_keep(k, setNames(fit$hfsat$mean, fit$hfsat$cols), fit$hfsat$cov,
                   function(z) round(z[, "FSC"]) >= FSC_FLOOR & round(z[, "FSC"]) < TOP)
    parts$hfsat <- cbind(SSC = clip8(z[, "SSC"]), SFL = TOP, FSC = round(z[, "FSC"]), FSCW = clip8(z[, "FSCW"]))
  }
  # core clusters: truncated so they never land in another class's region
  in_core <- function(z) {
    r <- round(z)
    r[, "SFL"] >= 16 & r[, "SFL"] < TOP & r[, "FSC"] >= FSC_FLOOR & r[, "FSC"] < TOP &
      r[, "SSC"] >= 0 & r[, "SSC"] < TOP & r[, "FSCW"] >= 0 & r[, "FSCW"] < TOP
  }
  for (j in seq_along(fit$clusters)) {
    k <- counts[3 + j]
    c <- fit$clusters[[j]]
    if (k > 0) parts[[paste0("core", j)]] <- round(rmvn_keep(k, c$mean, c$cov, in_core))
  }

  ev <- do.call(rbind, lapply(parts, function(p) p[, SIGNALS, drop = FALSE]))
  pop <- rep(names(parts), vapply(parts, nrow, 1L))
  o <- sample(nrow(ev))  # real files carry no order information
  storage.mode(ev) <- "integer"
  list(events = ev[o, , drop = FALSE], pop = pop[o])
}
