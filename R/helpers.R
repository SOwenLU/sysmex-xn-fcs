# Shared helpers: FCS discovery, file-to-S1..S4 mapping, raw-parser bridge, redaction,
# channel-role mapping, and a memoised event loader. Sourced by every numbered script.

suppressPackageStartupMessages({
  library(flowCore)
  library(jsonlite)
  library(digest)
})

FCS_MAGIC <- c("FCS2.0", "FCS3.0", "FCS3.1")

# ---- discovery & mapping -------------------------------------------------------------

sniff_magic <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con))
  b <- readBin(con, "raw", 6)
  if (length(b) < 6 || any(b == as.raw(0))) return(NA_character_)
  rawToChar(b)
}

discover_inputs <- function(cfg) {
  paths <- list.files(cfg$input_dir, full.names = TRUE, all.files = FALSE, no.. = TRUE)
  paths <- paths[!dir.exists(paths)]
  if (!length(paths)) stop("no files in ", cfg$input_dir, call. = FALSE)
  magic <- vapply(paths, sniff_magic, "")
  is_fcs <- !is.na(magic) & magic %in% FCS_MAGIC
  for (p in paths[!is_fcs]) warning("skipping non-FCS file: ", basename(p), call. = FALSE)
  data.frame(
    file = basename(paths),
    path = paths,
    size_bytes = file.size(paths),
    sha256 = vapply(paths, function(p) digest(file = p, algo = "sha256"), ""),
    magic = ifelse(is.na(magic), "", magic),
    is_fcs = is_fcs,
    stringsAsFactors = FALSE, row.names = NULL
  )
}

label_from_name <- function(name) {
  hits <- regmatches(name, gregexpr("(?i)(?<![a-z0-9])s0*([1-4])(?![0-9])", name, perl = TRUE))[[1]]
  nums <- unique(sub("(?i)^s0*", "", hits, perl = TRUE))
  if (length(nums) == 1) paste0("S", nums) else NA_character_
}

# Returns the manifest with a `label` column, or stops with a listing if mapping is ambiguous.
map_labels <- function(man, manual_map = NULL) {
  fcs <- man$is_fcs
  man$label <- NA_character_
  man$label_source <- NA_character_
  if (!is.null(manual_map)) {
    for (lab in names(manual_map)) {
      hit <- man$file == manual_map[[lab]]
      if (!any(hit)) stop("--map names a file that is not in the folder: ", manual_map[[lab]], call. = FALSE)
      man$label[hit] <- lab
      man$label_source[hit] <- "--map argument"
    }
  } else {
    man$label[fcs] <- vapply(man$file[fcs], label_from_name, "")
    man$label_source[fcs & !is.na(man$label)] <- "filename"
  }
  labs <- man$label[fcs]
  ambiguous <- any(is.na(labs)) || anyDuplicated(labs) > 0
  if (ambiguous) {
    cat("\nCould not map FCS files to S1-S4 unambiguously. Files found:\n")
    print(man[fcs, c("file", "size_bytes", "magic", "label")], row.names = FALSE)
    cat("\nRe-run with: --map S1=<file>,S2=<file>,S3=<file>,S4=<file>\n")
    quit(status = 2, save = "no")
  }
  man
}

# ---- raw parser bridge ---------------------------------------------------------------

.raw_cache <- new.env()

# Calls the independent Python parser. Output stays in memory: keyword values are only
# written to disk after redact_keywords().
raw_parse <- function(path, cfg) {
  key <- normalizePath(path)
  if (!is.null(.raw_cache[[key]])) return(.raw_cache[[key]])
  out <- system2(cfg$python, c("-I", shQuote(cfg$raw_parser), shQuote(path)),
                 stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop("raw parser failed on ", basename(path), ": ", paste(out, collapse = "\n"), call. = FALSE)
  }
  res <- fromJSON(paste(out, collapse = ""), simplifyVector = FALSE)
  .raw_cache[[key]] <- res
  res
}

raw_keywords <- function(ds) {
  segs <- list(TEXT = ds$text$pairs,
               STEXT = ds[["supplemental_text"]][["pairs"]],
               ANALYSIS = ds[["analysis_text"]][["pairs"]])
  rows <- lapply(names(segs), function(s) {
    p <- segs[[s]]
    if (!length(p)) return(NULL)
    data.frame(keyword = vapply(p, `[[`, "", 1), value = vapply(p, `[[`, "", 2),
               segment = s, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

kw_get <- function(kw, key, default = NA_character_) {
  v <- kw$value[toupper(kw$keyword) == toupper(key)]
  if (length(v)) v[1] else default
}

# ---- redaction -----------------------------------------------------------------------

# Values of these keywords are structural and kept verbatim.
STRUCTURAL_RE <- paste0(
  "^\\$P[0-9]+[A-Z]+$|^\\$(BEGIN|END)(ANALYSIS|DATA|STEXT)$|",
  "^\\$(NEXTDATA|TOT|PAR|DATATYPE|BYTEORD|MODE|TIMESTEP|SPILLOVER|SPILL|ABRT|LOST|",
  "CSMODE|CSVBITS|UNICODE|GATE|CYT|CYTSN|SYS|INST|FCSVERSION|CYTOLIB_VERSION|VOL|TR)$|",
  "^\\$(G|R|PK|PKN)[0-9]+[A-Z]*$|^\\$COMP$|^transformation$|^GUID$|^ORIGINALGUID$"
)
# Keyword names that may carry patient, sample or operator identity.
IDENTITY_NAME_RE <- paste0(
  "(?i)SMNO|^\\$SRC$|^\\$FIL$|FILENAME|PATIENT|PAT_?ID|SAMPLE|SPECIMEN|NAME|^\\$OP$|",
  "OPERATOR|USER|BARCODE|(^|[^A-Z])ID($|[^A-Z])|^\\$PROJ$|^\\$COM$|COMMENT|^\\$CELLS$|",
  "^\\$EXP$|WELL|PLATE|ACCESSION|MRN|HOSP|DOB|BIRTH|SEX|GENDER|AGE$|WARD|SEQ"
)
DATE_NAME_RE <- "(?i)DATE|LAST_MODIFIED|^\\$BTIM$|^\\$ETIM$|TIME_?STAMP"
DATE_VALUE_RE <- paste0(
  "(?i)\\b[0-9]{1,4}[-/.][0-9]{1,2}[-/.][0-9]{1,4}\\b|",
  "\\b[0-9]{1,2}[- ]?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*[- ]?[0-9]{2,4}\\b"
)

# Keeps the shape of a value (digits -> 9, letters -> X) so the schema can reproduce its format.
mask_value <- function(v) gsub("[A-Za-z]", "X", gsub("[0-9]", "9", v))

redact_keywords <- function(kw) {
  kw$redacted <- FALSE
  kw$redaction_reason <- ""
  structural <- grepl(STRUCTURAL_RE, kw$keyword, ignore.case = TRUE)
  numeric_only <- grepl("^\\s*-?[0-9]+(\\.[0-9]+)?([eE][-+]?[0-9]+)?\\s*$", kw$value)
  rules <- list(
    "keyword name suggests an identifier" = !structural & grepl(IDENTITY_NAME_RE, kw$keyword, perl = TRUE),
    "date/time keyword" = !structural & grepl(DATE_NAME_RE, kw$keyword, perl = TRUE),
    "date-like value" = !structural & grepl(DATE_VALUE_RE, kw$value, perl = TRUE),
    "ID-like value (5+ digit run in a non-numeric string)" =
      !structural & !numeric_only & grepl("[0-9]{5,}", kw$value),
    "long free-text value" = !structural & nchar(kw$value) > 64
  )
  for (reason in names(rules)) {
    hit <- rules[[reason]] & !kw$redacted
    kw$redacted[hit] <- TRUE
    kw$redaction_reason[hit] <- reason
  }
  kw$value[kw$redacted] <- paste0("[REDACTED; shape=", mask_value(kw$value[kw$redacted]), "]")
  kw
}

# ---- channel roles -------------------------------------------------------------------

# Maps $PnN/$PnS onto the WDF signals. Order matters: FSCW must be tested before FSC.
ROLE_PATTERNS <- c(
  FSCW = "(?i)FSC[-_ ]?W|FS[-_ ]?W\\b|\\bFW\\b|WIDTH|TOF|TIME[-_ ]?OF[-_ ]?FLIGHT",
  TIME = "(?i)^TIME$|\\bTIME\\b(?!.*FLIGHT)",
  INDEX = "(?i)EVENT|COUNT|INDEX|^ID$",
  SFL = "(?i)SFL|\\bFL\\b|FLUOR|\\bSF\\b",
  SSC = "(?i)SSC|\\bSS\\b|SIDE[-_ ]?SCAT",
  FSC = "(?i)FSC|\\bFS\\b|FORWARD"
)

channel_role <- function(pnn, pns = "") {
  txt <- paste(pnn, ifelse(is.na(pns), "", pns))
  for (r in names(ROLE_PATTERNS)) if (grepl(ROLE_PATTERNS[[r]], pnn, perl = TRUE)) return(r)
  for (r in names(ROLE_PATTERNS)) if (grepl(ROLE_PATTERNS[[r]], txt, perl = TRUE)) return(r)
  "other"
}

# ---- event loading -------------------------------------------------------------------

READ_ARGS <- list(transformation = FALSE, truncate_max_range = FALSE, emptyValue = FALSE)
.events_cache <- new.env()

# Fallback when flowCore fails: reads byte-aligned list-mode DATA using the raw parser's offsets.
manual_read <- function(path, ds) {
  d <- ds$data
  if (!isTRUE(d$supported)) stop("manual reader cannot decode: ", d$reason)
  begin <- ds$offsets_resolved$data_begin_abs
  con <- file(path, "rb")
  on.exit(close(con))
  seek(con, begin)
  bits <- unlist(d$bits)
  endian <- if (grepl("^4|^2,1|^8", gsub(" ", "", d$byteord))) "big" else "little"
  n <- d$events_from_data_length
  bytes <- readBin(con, "raw", n * d$bytes_per_event)
  if (d$datatype == "I" && length(unique(bits)) == 1) {
    size <- bits[1] / 8
    v <- readBin(bytes, "integer", n = n * d$n_par, size = size, signed = size > 2, endian = endian)
    if (size == 4) v[v < 0] <- v[v < 0] + 2^32
  } else if (d$datatype %in% c("F", "D")) {
    size <- if (d$datatype == "F") 4 else 8
    v <- readBin(bytes, "double", n = n * d$n_par, size = size, endian = endian)
  } else {
    stop("manual reader supports uniform-width I, F or D only")
  }
  matrix(as.numeric(v), ncol = d$n_par, byrow = TRUE)
}

# Returns list(mat, ff, reader, error, warnings) for one dataset. Memoised per process.
load_events <- function(path, dataset, n_datasets, cfg) {
  key <- paste(normalizePath(path), dataset)
  if (!is.null(.events_cache[[key]])) return(.events_cache[[key]])
  warns <- character()
  args <- c(list(filename = path), READ_ARGS)
  if (n_datasets > 1) args$dataset <- dataset
  ff <- tryCatch(
    withCallingHandlers(do.call(read.FCS, args),
                        warning = function(w) {
                          warns <<- c(warns, conditionMessage(w))
                          invokeRestart("muffleWarning")
                        }),
    error = function(e) e
  )
  if (inherits(ff, "error")) {
    msg <- conditionMessage(ff)
    message("flowCore FAILED on ", basename(path), " dataset ", dataset, ": ", msg,
            " -- falling back to manual reader")
    raw <- raw_parse(path, cfg)
    mat <- manual_read(path, raw$datasets[[dataset]])
    res <- list(mat = mat, ff = NULL, reader = "manual (flowCore failed)", error = msg, warnings = warns)
  } else {
    res <- list(mat = exprs(ff), ff = ff, reader = "flowCore", error = "", warnings = warns)
  }
  .events_cache[[key]] <- res
  res
}

write_out <- function(df, cfg, name) {
  path <- file.path(cfg$out_dir, name)
  write.csv(df, path, row.names = FALSE, na = "")
  cat("  wrote", name, "(", nrow(df), "rows )\n")
  invisible(path)
}

read_out <- function(cfg, name) {
  read.csv(file.path(cfg$out_dir, name), stringsAsFactors = FALSE, check.names = FALSE,
           na.strings = "")
}
