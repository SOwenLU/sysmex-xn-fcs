# Minimal writer for FCS files in the Sysmex XN layout seen in the real files (outputs/schema.json):
# FCS3.0, TEXT at byte 58, '/' delimiter, 10-digit zero-padded offset keywords, 8-bit unsigned
# list-mode DATA in the order SSC, SFL, FSC, FSCW, nothing after DATA.
# Keyword order and HEADER field padding are not recorded in the outputs: TBD against the raw files.

XN_PARAMS <- data.frame(
  N = c("SSC", "SFL", "FSC", "FSCW"),
  S = c("Side Scatter Signal", "Side Fluorescence Signal", "Forward Scatter Signal",
        "Forward Scatter Pulse Width Signal"),
  stringsAsFactors = FALSE
)

# events: integer matrix [n x 4] with columns SSC, SFL, FSC, FSCW and values 0..255.
# keywords: named character vector of the non-structural keywords ($CYT, $FIL, $SMNO, ...).
write_xn_fcs <- function(events, keywords, path) {
  stopifnot(is.matrix(events), identical(colnames(events), XN_PARAMS$N),
            all(events >= 0 & events <= 255), all(events == round(events)))
  data <- as.raw(as.vector(t(events)))  # event by event, one byte per parameter

  pad10 <- function(x) sprintf("%010d", as.integer(x))
  kv <- c("$BEGINANALYSIS" = pad10(0), "$ENDANALYSIS" = pad10(0),
          "$BEGINSTEXT" = pad10(0), "$ENDSTEXT" = pad10(0), "$NEXTDATA" = pad10(0),
          "$BEGINDATA" = pad10(0), "$ENDDATA" = pad10(0),
          "$BYTEORD" = "1,2,3,4", "$DATATYPE" = "I", "$MODE" = "L",
          "$PAR" = "4", "$TOT" = as.character(nrow(events)))
  for (p in seq_len(nrow(XN_PARAMS))) {
    kv[sprintf("$P%dN", p)] <- XN_PARAMS$N[p]
    kv[sprintf("$P%dS", p)] <- XN_PARAMS$S[p]
    kv[sprintf("$P%dB", p)] <- "8"
    kv[sprintf("$P%dR", p)] <- "256"
    kv[sprintf("$P%dE", p)] <- "0,0"
  }
  kv <- c(kv, keywords)
  kv <- kv[order(names(kv))]

  build_text <- function(kv) {
    esc <- function(x) gsub("/", "//", x, fixed = TRUE)
    paste0("/", paste0(esc(names(kv)), "/", esc(kv), "/", collapse = ""))
  }
  # Offsets are fixed-width, so the TEXT length does not depend on their values.
  text_len <- nchar(build_text(kv), type = "bytes")
  begin <- 58 + text_len
  end <- begin + length(data) - 1
  kv["$BEGINDATA"] <- pad10(begin)
  kv["$ENDDATA"] <- pad10(end)
  txt <- build_text(kv)
  stopifnot(nchar(txt, type = "bytes") == text_len)

  hdr_num <- function(x) formatC(x, width = 8, format = "d")
  header <- paste0("FCS3.0    ", hdr_num(58), hdr_num(57 + text_len), hdr_num(begin), hdr_num(end),
                   hdr_num(0), hdr_num(0))
  stopifnot(nchar(header) == 58)
  writeBin(c(charToRaw(header), charToRaw(txt), data), path)
  invisible(path)
}

# Fabricated keyword values in the shapes seen in the real files (keywords_all.csv).
xn_fake_keywords <- function(smno, when, serial = "90001") {
  stopifnot(grepl("^[A-Z]{2}-[0-9]{2}$", smno))
  c("$CYT" = "XN-20", "$CYTSN" = serial, "$SYS" = "Windows 7", "$ORIGINALITY" = "Original",
    "$CELLS" = "SY", "$COM" = "SYNTHC",
    "$DATE" = format(when, "%d-%m-%Y"), "$ETIM" = format(when, "%H:%M:%S"), "$SMNO" = smno,
    "$FIL" = sprintf("[XN-20^%s][00-00_0][%s][%22s].000", serial, format(when, "%Y%m%d_%H%M%S"), smno))
}
