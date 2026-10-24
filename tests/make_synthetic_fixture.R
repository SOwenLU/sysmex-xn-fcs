# Generates a fully fabricated FCS fixture for testing the pipeline. No real record is used.
#
#   Rscript tests/make_synthetic_fixture.R <fixture_folder>
#
# Writes four FCS3.0 files under PLOS-style names without an extension (s004 holds two
# datasets via $NEXTDATA), plus one non-FCS file that the pipeline should skip.
# Includes fake identifier and date keywords to exercise redaction.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("usage: Rscript tests/make_synthetic_fixture.R <fixture_folder>")
out <- args[1]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
set.seed(20261022)

PAR_NAMES <- c("FSC", "SSC", "SFL", "FSCW")

fake_events <- function(n) {
  # Two fabricated clusters plus a sparse high-FSCW/high-SFL tail; 10-bit range.
  k <- rbinom(1, n, 0.6)
  a <- cbind(rnorm(k, 300, 40), rnorm(k, 200, 50), rnorm(k, 250, 40), rnorm(k, 120, 15))
  b <- cbind(rnorm(n - k, 420, 60), rnorm(n - k, 600, 80), rnorm(n - k, 180, 30), rnorm(n - k, 130, 20))
  m <- rbind(a, b)
  tail <- sample(n, n %/% 50)
  m[tail, 3] <- m[tail, 3] + 300
  m[tail, 4] <- m[tail, 4] + 200
  pmin(pmax(round(m), 0), 1023)
}

build_text <- function(kv, delim = "|") {
  esc <- function(x) gsub(delim, paste0(delim, delim), x, fixed = TRUE)
  paste0(delim, paste0(esc(names(kv)), delim, esc(kv), delim, collapse = ""))
}

# Returns the raw bytes of one dataset (HEADER + TEXT + DATA); nextdata is relative.
build_dataset <- function(mat, extra_kw, nextdata_fn = function(len) 0) {
  data <- writeBin(as.integer(t(mat)), raw(), size = 2, endian = "little")
  kv <- c("$BEGINANALYSIS" = "0", "$ENDANALYSIS" = "0", "$BEGINSTEXT" = "0", "$ENDSTEXT" = "0",
          "$BYTEORD" = "1,2", "$DATATYPE" = "I", "$MODE" = "L", "$PAR" = as.character(ncol(mat)),
          "$TOT" = as.character(nrow(mat)))
  for (p in seq_along(PAR_NAMES)) {
    kv[sprintf("$P%dN", p)] <- PAR_NAMES[p]
    kv[sprintf("$P%dB", p)] <- "16"
    kv[sprintf("$P%dR", p)] <- "1024"
    kv[sprintf("$P%dE", p)] <- "0,0"
  }
  kv <- c(kv, extra_kw)
  # Iterate offsets until the TEXT length is stable
  begin <- end <- nxt <- 0
  repeat {
    kv[c("$BEGINDATA", "$ENDDATA", "$NEXTDATA")] <- as.character(c(begin, end, nxt))
    txt <- charToRaw(build_text(kv))
    nb <- 58 + length(txt)
    ne <- nb + length(data) - 1
    nn <- nextdata_fn(ne + 1)
    if (nb == begin && ne == end && nn == nxt) break
    begin <- nb; end <- ne; nxt <- nn
  }
  pad8 <- function(x) formatC(x, width = 8, format = "d")
  header <- charToRaw(paste0("FCS3.0    ", pad8(58), pad8(57 + length(txt)),
                             pad8(begin), pad8(end), pad8(0), pad8(0)))
  c(header, txt, data)
}

fake_kw <- function(i) c("$CYT" = "SYN-ANALYSER", "$DATE" = "01-JAN-2000",
                         "$BTIM" = "10:00:00", "$ETIM" = "10:01:30",
                         "SAMPLE ID" = sprintf("SYN-%07d", i), "SYN_MODE" = "BF",
                         "$FIL" = sprintf("SYN%05d.FCS", i))

for (i in 1:4) {
  ds1 <- build_dataset(fake_events(1000 * i), fake_kw(i),
                       if (i == 4) function(len) len else function(len) 0)
  bytes <- if (i == 4) c(ds1, build_dataset(fake_events(500), fake_kw(40))) else ds1
  writeBin(bytes, file.path(out, sprintf("journal.pone.0190886.s%03d", i)))
}
writeLines("not an FCS file", file.path(out, "notes.txt"))
cat("Synthetic fixture written to", out, "\n")
