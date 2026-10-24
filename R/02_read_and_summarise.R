# 02 — Read every dataset with flowCore (no transformation, no truncation), cross-check
# against the independent raw parser, and summarise keywords, parameters and events.
#
# Writes: keywords_all.csv, parameters.csv, event_summary.csv, reader_status.csv
#         events/<label>_ds<n>_events.csv (only with --export-events)

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
source(file.path(PROJECT_DIR, "R", "paths.R"))
source(file.path(PROJECT_DIR, "R", "helpers.R"))
if (!exists("cfg")) cfg <- get_config()

cat("\n== 02 read and summarise ==\n")
man <- read_out(cfg, "inputs_manifest.csv")
man <- man[man$is_fcs, ]
man$path <- file.path(cfg$input_dir, man$file)

PN_MAIN <- c("N", "S", "B", "R", "E", "G", "D", "V")

# Percent of events in the outermost 1% of the observed range. A natural tail puts very few
# events there; a trigger threshold, saturation or gate leaves a hard edge with many.
pct_at_edge <- function(x, at = c("low", "high")) {
  at <- match.arg(at)
  w <- (max(x) - min(x)) / 100
  if (w <= 0) return(NA_real_)
  100 * mean(if (at == "low") x < min(x) + w else x > max(x) - w)
}

if (cfg$export_events) {
  ev_dir <- file.path(cfg$out_dir, "events")
  dir.create(ev_dir, showWarnings = FALSE)
}

kw_rows <- list(); par_rows <- list(); ev_rows <- list(); status_rows <- list()

for (i in seq_len(nrow(man))) {
  f <- man[i, ]
  raw <- raw_parse(f$path, cfg)
  for (ds in raw$datasets) {
    n <- ds$dataset
    rk <- raw_keywords(ds)
    ev <- load_events(f$path, n, raw$n_datasets, cfg)

    # -- keywords: raw TEXT vs flowCore, compared before redaction --------------------
    fk <- if (!is.null(ev$ff)) keyword(ev$ff) else list()
    fk <- data.frame(keyword = names(fk),
                     value_fc = vapply(fk, function(v) paste(v, collapse = " "), ""),
                     stringsAsFactors = FALSE)
    rk$key_up <- toupper(rk$keyword)
    fk$key_up <- toupper(fk$keyword)
    kw <- merge(rk, fk[, c("key_up", "value_fc", "keyword")], by = "key_up", all = TRUE,
                suffixes = c("", "_fc"))
    kw$in_raw_text <- !is.na(kw$value)
    kw$in_flowcore <- !is.na(kw$value_fc)
    kw$keyword <- ifelse(is.na(kw$keyword), kw$keyword_fc, kw$keyword)
    kw$segment[is.na(kw$segment)] <- "added by flowCore"
    kw$values_match_flowcore <- ifelse(kw$in_raw_text & kw$in_flowcore,
                                       trimws(kw$value) == trimws(kw$value_fc), NA)
    kw$value <- ifelse(kw$in_raw_text, kw$value, kw$value_fc)
    if ("FILENAME" %in% kw$key_up) kw$value[kw$key_up == "FILENAME"] <- f$file  # no local paths
    kw <- redact_keywords(kw[, c("keyword", "value", "segment", "in_raw_text", "in_flowcore",
                                 "values_match_flowcore")])
    kw$standard <- startsWith(kw$keyword, "$")
    kw$nonstandard_in_file <- !kw$standard & kw$segment != "added by flowCore"
    kw_rows[[length(kw_rows) + 1]] <- cbind(label = f$label, file = f$file, dataset = n, kw,
                                            stringsAsFactors = FALSE)

    # -- parameters --------------------------------------------------------------------
    npar <- as.integer(kw_get(rk, "$PAR"))
    pd <- if (!is.null(ev$ff)) pData(parameters(ev$ff)) else NULL
    for (p in seq_len(npar)) {
      vals <- setNames(lapply(PN_MAIN, function(s) kw_get(rk, sprintf("$P%d%s", p, s))),
                       paste0("Pn", PN_MAIN))
      own <- rk[grepl(sprintf("^\\$P%d[A-Z]+$", p), rk$keyword, ignore.case = TRUE), ]
      extra <- own[!toupper(own$keyword) %in% sprintf("$P%d%s", p, PN_MAIN), ]
      par_rows[[length(par_rows) + 1]] <- data.frame(
        label = f$label, file = f$file, dataset = n, index = p, vals,
        other_Pn_keywords = paste(sprintf("%s=%s", extra$keyword, extra$value), collapse = "; "),
        role = channel_role(vals$PnN, vals$PnS),
        flowcore_name = if (!is.null(pd)) pd$name[p] else NA,
        flowcore_range = if (!is.null(pd)) pd$range[p] else NA,
        flowcore_maxRange = if (!is.null(pd)) pd$maxRange[p] else NA,
        stringsAsFactors = FALSE
      )
    }

    # -- events ------------------------------------------------------------------------
    m <- ev$mat
    tot <- as.numeric(kw_get(rk, "$TOT"))
    rs <- ds$data$param_stats
    for (p in seq_len(ncol(m))) {
      x <- m[, p]
      pnr <- suppressWarnings(as.numeric(kw_get(rk, sprintf("$P%dR", p))))
      q <- quantile(x, c(0.01, 0.5, 0.99), names = FALSE, type = 7)
      ints <- all(x == round(x))
      span <- if (ints) max(x) - min(x) + 1 else NA
      raw_ok <- if (length(rs) >= p) {
        r <- rs[[p]]
        r$n == length(x) && r$min == min(x) && r$max == max(x) &&
          isTRUE(all.equal(r$mean, mean(x), tolerance = 1e-9)) && r$n_unique == length(unique(x))
      } else NA
      ev_rows[[length(ev_rows) + 1]] <- data.frame(
        label = f$label, file = f$file, dataset = n, index = p,
        PnN = kw_get(rk, sprintf("$P%dN", p)), role = channel_role(kw_get(rk, sprintf("$P%dN", p)),
                                                                     kw_get(rk, sprintf("$P%dS", p))),
        TOT = tot, rows = length(x), TOT_equals_rows = tot == length(x),
        min = min(x), max = max(x), mean = mean(x), median = q[2], sd = sd(x),
        p01 = q[1], p99 = q[3], n_unique = length(unique(x)), all_integer = ints,
        bits_needed_for_max = if (ints && max(x) >= 0) ceiling(log2(max(x) + 1)) else NA,
        PnR = pnr,
        prop_zero = mean(x == 0),
        prop_at_observed_max = mean(x == max(x)),
        prop_at_PnR_minus_1 = if (!is.na(pnr)) mean(x == pnr - 1) else NA,
        prop_ge_PnR = if (!is.na(pnr)) mean(x >= pnr) else NA,
        prop_unused_integer_values_in_range = if (ints && span <= 1e6) 1 - length(unique(x)) / span else NA,
        pct_in_lowest_1pct_of_range = pct_at_edge(x, "low"),
        pct_in_highest_1pct_of_range = pct_at_edge(x, "high"),
        reader = ev$reader,
        matches_raw_parser = raw_ok,
        stringsAsFactors = FALSE
      )
    }
    # -- per-event export (opt-in) -------------------------------------------------------
    if (cfg$export_events) {
      cols <- vapply(seq_len(ncol(m)), function(p) kw_get(rk, sprintf("$P%dN", p)), "")
      cols[is.na(cols) | cols == ""] <- sprintf("P%d", which(is.na(cols) | cols == ""))
      per_event <- data.frame(event = seq_len(nrow(m)), m)
      names(per_event) <- c("event", make.unique(cols))
      write_out(per_event, list(out_dir = ev_dir), sprintf("%s_ds%d_events.csv", f$label, n))
    }

    status_rows[[length(status_rows) + 1]] <- data.frame(
      label = f$label, file = f$file, dataset = n, reader = ev$reader,
      flowcore_error = ev$error, flowcore_warnings = paste(unique(ev$warnings), collapse = " | "),
      rows = nrow(m), cols = ncol(m), stringsAsFactors = FALSE
    )
    cat("  ", f$label, "dataset", n, ":", nrow(m), "events x", ncol(m), "parameters via", ev$reader, "\n")
  }
}

kw_all <- do.call(rbind, kw_rows)
write_out(kw_all, cfg, "keywords_all.csv")
write_out(do.call(rbind, par_rows), cfg, "parameters.csv")
ev_all <- do.call(rbind, ev_rows)
write_out(ev_all, cfg, "event_summary.csv")
write_out(do.call(rbind, status_rows), cfg, "reader_status.csv")
cat("  redacted keyword values:", sum(kw_all$redacted), "\n")
cat("  flowCore vs raw-parser event checks passing:", sum(ev_all$matches_raw_parser, na.rm = TRUE),
    "of", nrow(ev_all), "\n")
