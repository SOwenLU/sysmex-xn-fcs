# 01 — Find FCS files, map them to S1-S4, hash them, and report byte-level structure
# from the independent Python parser (HEADER offsets, delimiter, datasets, ANALYSIS).
#
# Writes: inputs_manifest.csv, header_structure.csv

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
source(file.path(PROJECT_DIR, "R", "paths.R"))
source(file.path(PROJECT_DIR, "R", "helpers.R"))
if (!exists("cfg")) cfg <- get_config()

cat("\n== 01 inspect header ==\n")
man <- discover_inputs(cfg)
man <- map_labels(man, cfg$manual_map)
man <- merge(man, PAPER_TABLE, by = "label", all.x = TRUE, sort = FALSE)
man <- man[order(man$label, man$file), ]
cat("  ", sum(man$is_fcs), "FCS file(s),", sum(!man$is_fcs), "skipped\n")

btim_etim_seconds <- function(b, e) {
  to_s <- function(x) {
    p <- as.numeric(strsplit(sub("[.:][0-9]+$", "", x), ":", fixed = TRUE)[[1]])
    if (length(p) != 3 || anyNA(p)) return(NA_real_)
    sum(p * c(3600, 60, 1))
  }
  if (is.na(b) || is.na(e)) return(NA_real_)
  d <- to_s(e) - to_s(b)
  if (!is.na(d) && d < 0) d <- d + 86400
  d
}

rows <- list()
for (i in which(man$is_fcs)) {
  raw <- raw_parse(man$path[i], cfg)
  stopifnot(identical(raw$file_sha256, man$sha256[i]))  # R and Python hashed the same bytes
  for (ds in raw$datasets) {
    kw <- raw_keywords(ds)
    h <- ds$header
    o <- h$offsets
    d <- ds$data
    rows[[length(rows) + 1]] <- data.frame(
      label = man$label[i], file = man$file[i], dataset = ds$dataset,
      n_datasets_in_file = raw$n_datasets,
      dataset_base_offset = ds$base_offset,
      version = h$version,
      header_spacer_is_4_spaces = h$spacer_is_spaces,
      hdr_text_begin = o$text_begin %||% NA, hdr_text_end = o$text_end %||% NA,
      hdr_data_begin = o$data_begin %||% NA, hdr_data_end = o$data_end %||% NA,
      hdr_analysis_begin = o$analysis_begin %||% NA, hdr_analysis_end = o$analysis_end %||% NA,
      hdr_other_segments = length(h$other_segment_fields),
      kw_begindata = kw_get(kw, "$BEGINDATA"), kw_enddata = kw_get(kw, "$ENDDATA"),
      header_vs_keyword_offsets_agree = ds$data_offsets_header_vs_keyword_agree %||% NA,
      text_delimiter = ds$text$delimiter,
      text_delimiter_ascii_code = ds$text$delimiter_ord,
      text_n_keywords = length(ds$text$pairs),
      text_odd_token_count = ds$text$odd_token_count,
      text_ends_with_delimiter = ds$text$ends_with_delimiter,
      DATATYPE = kw_get(kw, "$DATATYPE"), BYTEORD = kw_get(kw, "$BYTEORD"),
      MODE = kw_get(kw, "$MODE"), PAR = kw_get(kw, "$PAR"), TOT = kw_get(kw, "$TOT"),
      NEXTDATA = kw_get(kw, "$NEXTDATA"),
      multiple_datasets = raw$n_datasets > 1,
      analysis_segment_present = ds$analysis_segment_present,
      analysis_segment_bytes = ds$analysis_segment_bytes,
      supplemental_text_present = ds$supplemental_text_present,
      data_bytes = d$data_bytes %||% NA,
      bytes_per_event = d$bytes_per_event %||% NA,
      events_from_data_length = d$events_from_data_length %||% NA,
      data_length_remainder_bytes = d$data_length_remainder %||% NA,
      data_segment_sha256 = d$data_sha256 %||% NA,
      raw_parser_decoded_data = isTRUE(d$supported),
      raw_parser_note = d$reason %||% "",
      acquisition_duration_s = btim_etim_seconds(kw_get(kw, "$BTIM"), kw_get(kw, "$ETIM")),
      file_trailing_bytes = raw$trailing_bytes,
      file_trailing_is_crc_like = raw$trailing_is_crc_like,
      stringsAsFactors = FALSE
    )
  }
}
hdr <- do.call(rbind, rows)

write_out(man[, setdiff(names(man), "path")], cfg, "inputs_manifest.csv")
write_out(hdr, cfg, "header_structure.csv")
print(hdr[, c("label", "dataset", "version", "DATATYPE", "BYTEORD", "MODE", "PAR", "TOT",
              "NEXTDATA", "analysis_segment_present")], row.names = FALSE)
