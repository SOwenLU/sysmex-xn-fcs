# 04 — Build schema.json (spec for a synthetic XN FCS generator) and report.md from the
# CSVs written by 01-02. Works only from those (already redacted) summaries.
#
# Writes: schema.json, report.md, sessionInfo.txt

if (!exists("PROJECT_DIR")) {
  .f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  PROJECT_DIR <- normalizePath(file.path(dirname(.f), ".."))
}
source(file.path(PROJECT_DIR, "R", "paths.R"))
source(file.path(PROJECT_DIR, "R", "helpers.R"))
if (!exists("cfg")) cfg <- get_config()

cat("\n== 04 schema and report ==\n")
man_all <- read_out(cfg, "inputs_manifest.csv")
man <- man_all[man_all$is_fcs, ]
hdr <- read_out(cfg, "header_structure.csv")
kw <- read_out(cfg, "keywords_all.csv")
pars <- read_out(cfg, "parameters.csv")
ev <- read_out(cfg, "event_summary.csv")
st <- read_out(cfg, "reader_status.csv")

# Required TEXT keywords per FCS spec ($Pn* expanded per parameter in the generator).
SPEC_REQUIRED <- list(
  "FCS2.0" = c("$BYTEORD", "$DATATYPE", "$MODE", "$NEXTDATA", "$PAR", "$PnB", "$PnR"),
  "FCS3.0" = c("$BEGINANALYSIS", "$BEGINDATA", "$BEGINSTEXT", "$BYTEORD", "$DATATYPE",
               "$ENDANALYSIS", "$ENDDATA", "$ENDSTEXT", "$MODE", "$NEXTDATA", "$PAR",
               "$TOT", "$PnB", "$PnE", "$PnN", "$PnR"),
  "FCS3.1" = c("$BEGINANALYSIS", "$BEGINDATA", "$BEGINSTEXT", "$BYTEORD", "$DATATYPE",
               "$ENDANALYSIS", "$ENDDATA", "$ENDSTEXT", "$MODE", "$NEXTDATA", "$PAR",
               "$TOT", "$PnB", "$PnE", "$PnN", "$PnR")
)
EXPORT_HINT_RE <- "(?i)CYT|SYS|SOFTWARE|CREATOR|VERSION|INST|SERIAL|SN$|MODEL|MODE|SERVICE|RESEARCH|EXPORT|PROGRAM|APPL|XN|SYSMEX"

uniq <- function(x) unique(x[!is.na(x)])
or_none <- function(x, sep = "; ") if (length(uniq(x[nzchar(x)]))) collapse(x[nzchar(x)], sep) else "none"
collapse <- function(x, sep = ", ") paste(uniq(x), collapse = sep)
fmt <- function(x, d = 3) ifelse(is.na(x), "NA", formatC(x, digits = d, format = "g"))
md_table <- function(df) {
  df[] <- lapply(df, function(c) gsub("\\|", "\\\\|", as.character(c)))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

file_kw <- kw[kw$segment != "added by flowCore", ]
file_kw$generic <- sub("^\\$P[0-9]+", "$Pn", file_kw$keyword)
n_sets <- nrow(unique(file_kw[, c("file", "dataset")]))
is_pn <- grepl("^\\$Pn", file_kw$generic)

# ---- schema.json ---------------------------------------------------------------------

kw_summary <- do.call(rbind, lapply(split(file_kw[!is_pn, ], file_kw$keyword[!is_pn]), function(d) {
  data.frame(keyword = d$keyword[1], n_datasets_present = nrow(unique(d[, c("file", "dataset")])),
             example_value = d$value[1], constant_across_files = length(unique(d$value)) == 1,
             redacted = any(d$redacted), sysmex_specific_candidate = !d$standard[1],
             segment = d$segment[1], stringsAsFactors = FALSE)
}))
kw_summary$in_all <- kw_summary$n_datasets_present == n_sets
versions <- uniq(hdr$version)
spec_req <- unique(unlist(SPEC_REQUIRED[versions]))

ref <- pars[pars$file == pars$file[1] & pars$dataset == 1, ]
same_params <- all(vapply(split(pars, paste(pars$file, pars$dataset)), function(p) {
  nrow(p) == nrow(ref) && all(p$PnN == ref$PnN) && all(p$PnB == ref$PnB) &&
    all(as.character(p$PnR) == as.character(ref$PnR))
}, TRUE))
param_spec <- lapply(seq_len(nrow(ref)), function(j) {
  e <- ev[ev$index == ref$index[j], ]
  list(index = ref$index[j], PnN = ref$PnN[j], PnS = ref$PnS[j], PnB = ref$PnB[j],
       PnR = ref$PnR[j], PnE = ref$PnE[j], PnG = ref$PnG[j], role = ref$role[j],
       other_Pn_keywords = ref$other_Pn_keywords[j],
       observed_min = min(e$min), observed_max = max(e$max),
       all_integer = all(e$all_integer),
       per_file = lapply(split(e, paste0(e$label, "_ds", e$dataset)), function(r)
         list(median = r$median, p01 = r$p01, p99 = r$p99, sd = r$sd)))
})

tot_by_set <- unique(ev[, c("label", "dataset", "TOT", "rows")])
schema <- list(
  generated_on = format(Sys.Date()),
  source = "Kaku N et al. PLOS ONE 2018; doi:10.1371/journal.pone.0190886, supplementary files S1-S4 (Sysmex XN-1000, XN-BF mode, WDF channel)",
  n_files = nrow(man),
  file_structure = list(
    fcs_version = versions,
    header_spacer_4_spaces = all(hdr$header_spacer_is_4_spaces),
    header_text_begin_offsets = uniq(hdr$hdr_text_begin),
    header_other_segments = max(hdr$hdr_other_segments),
    text_delimiter = uniq(hdr$text_delimiter),
    text_delimiter_ascii_code = uniq(hdr$text_delimiter_ascii_code),
    text_ends_with_delimiter = uniq(hdr$text_ends_with_delimiter),
    datasets_per_file = uniq(hdr$n_datasets_in_file),
    analysis_segment_present = any(hdr$analysis_segment_present),
    supplemental_text_present = any(hdr$supplemental_text_present),
    trailing_crc_like_bytes = any(hdr$file_trailing_is_crc_like),
    header_and_keyword_data_offsets_agree = uniq(hdr$header_vs_keyword_offsets_agree)
  ),
  encoding = list(DATATYPE = uniq(hdr$DATATYPE), BYTEORD = uniq(hdr$BYTEORD), MODE = uniq(hdr$MODE),
                  bytes_per_event = uniq(hdr$bytes_per_event)),
  parameters_identical_across_files = same_params,
  parameters = param_spec,
  keywords = list(
    spec_required = lapply(spec_req, function(k) {
      ex <- kw_summary[kw_summary$keyword == k, ]
      list(keyword = k, observed = nrow(ex) > 0 || grepl("^\\$Pn", k),
           example_value = if (nrow(ex)) ex$example_value else NULL)
    }),
    present_in_all_files = lapply(which(kw_summary$in_all), function(j) as.list(kw_summary[j, c(
      "keyword", "example_value", "constant_across_files", "redacted", "sysmex_specific_candidate", "segment")])),
    optional_observed = lapply(which(!kw_summary$in_all), function(j) as.list(kw_summary[j, c(
      "keyword", "n_datasets_present", "example_value", "redacted", "sysmex_specific_candidate", "segment")])),
    parameter_keywords_observed = sort(unique(file_kw$generic[is_pn]))
  ),
  event_count = list(min = min(tot_by_set$rows), max = max(tot_by_set$rows),
                     per_file = setNames(as.list(tot_by_set$rows), paste0(tot_by_set$label, "_ds", tot_by_set$dataset)),
                     TOT_equals_rows = all(tot_by_set$TOT == tot_by_set$rows)),
  not_inferable_from_these_files = c(
    "Whole-blood (XN WB mode) event counts and WDF cluster positions",
    "Other XN channels: WNR, WPC, RET, PLT-F, PLT-I/RBC (impedance)",
    "Normal or non-malignant body-fluid scattergrams (all four are malignant pleural effusions)",
    "Day-to-day / instrument-to-instrument calibration differences",
    "Whether a different export route (e.g. other IPU/service software version) changes keywords or encoding"
  )
)
write_json(schema, file.path(cfg$out_dir, "schema.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = NA)
cat("  wrote schema.json\n")

# ---- report.md -----------------------------------------------------------------------

L <- character()
add <- function(...) L <<- c(L, ...)
sig_ev <- ev[!ev$role %in% c("TIME", "INDEX"), ]

add("# Sysmex XN-1000 FCS characterisation (Kaku et al. 2018, S1-S4)", "",
    sprintf("Generated %s from `%d` FCS file(s); %d non-FCS file(s) skipped. All numbers come from the CSVs in this folder.",
            format(Sys.time(), "%Y-%m-%d %H:%M"), nrow(man), sum(!man_all$is_fcs)), "")

add("## Inputs", "", md_table(data.frame(
  label = man$label, file = man$file, bytes = man$size_bytes, sha256 = substr(man$sha256, 1, 16),
  paper_sample = man$paper_sample, diagnosis = man$diagnosis, rule1 = man$rule1, rule2 = man$rule2)),
  "", paste0("Full SHA-256 in `inputs_manifest.csv`. Mapping source: ", collapse(man$label_source), "."), "")

add("## 1. File structure", "")
add(sprintf("- **FCS version:** %s", collapse(hdr$version)),
    sprintf("- **Datasets per file:** %s (`$NEXTDATA` = %s)", collapse(hdr$n_datasets_in_file), collapse(hdr$NEXTDATA)),
    sprintf("- **HEADER:** TEXT starts at byte %s; DATA offsets in HEADER and `$BEGINDATA/$ENDDATA` agree: %s; extra OTHER segments: %s",
            collapse(hdr$hdr_text_begin), collapse(hdr$header_vs_keyword_offsets_agree), max(hdr$hdr_other_segments)),
    sprintf("- **TEXT delimiter:** `%s` (ASCII %s); TEXT ends with a delimiter: %s; %s keywords per file",
            collapse(hdr$text_delimiter), collapse(hdr$text_delimiter_ascii_code),
            collapse(hdr$text_ends_with_delimiter), collapse(hdr$text_n_keywords)),
    sprintf("- **Encoding:** `$DATATYPE`=%s, `$BYTEORD`=%s, `$MODE`=%s, %s bytes per event",
            collapse(hdr$DATATYPE), collapse(hdr$BYTEORD), collapse(hdr$MODE), collapse(hdr$bytes_per_event)),
    sprintf("- **ANALYSIS segment:** %s; supplemental TEXT: %s; trailing CRC-like bytes: %s",
            if (any(hdr$analysis_segment_present)) "present" else "absent",
            if (any(hdr$supplemental_text_present)) "present" else "absent",
            if (any(hdr$file_trailing_is_crc_like)) "yes" else "no"),
    sprintf("- **Readers:** %s. flowCore errors: %s. flowCore warnings: %s.",
            collapse(st$reader), or_none(st$flowcore_error), or_none(st$flowcore_warnings)),
    sprintf("- **Cross-check:** flowCore and the independent Python byte parser agree on n/min/max/mean/unique for %d of %d file x parameter rows; TEXT values match for %d of %d keywords present in both.",
            sum(ev$matches_raw_parser, na.rm = TRUE), nrow(ev),
            sum(kw$values_match_flowcore, na.rm = TRUE), sum(!is.na(kw$values_match_flowcore))), "")
mism <- kw[!is.na(kw$values_match_flowcore) & !kw$values_match_flowcore, ]
if (nrow(mism)) add("  Keywords whose flowCore value differs from the raw TEXT: ",
                    paste0("  `", unique(mism$keyword), "`", collapse = ","), "")

add("## 2. Parameters", "",
    sprintf("Parameter set identical across all files: **%s**.", same_params), "",
    md_table(data.frame(n = ref$index, PnN = ref$PnN, PnS = ifelse(is.na(ref$PnS), "(absent)", ref$PnS),
                        PnB = ref$PnB, PnR = ref$PnR, PnE = ifelse(is.na(ref$PnE), "(absent)", ref$PnE),
                        PnG = ifelse(is.na(ref$PnG), "(absent)", ref$PnG), `mapped role` = ref$role, check.names = FALSE)), "")
roles <- ref$role
add(sprintf("- WDF signals identified by name: %s.", paste(sprintf("%s → `%s`", roles[roles %in% c("FSC", "SSC", "SFL", "FSCW")],
                                                               ref$PnN[roles %in% c("FSC", "SSC", "SFL", "FSCW")]), collapse = ", ")),
    sprintf("- Missing WDF roles: %s.", if (all(c("FSC", "SSC", "SFL", "FSCW") %in% roles)) "none" else collapse(setdiff(c("FSC", "SSC", "SFL", "FSCW"), roles))),
    sprintf("- Extra parameters (time, IDs, flags, cluster labels, unmapped): %s.",
            if (any(!roles %in% c("FSC", "SSC", "SFL", "FSCW"))) paste0("`", ref$PnN[!roles %in% c("FSC", "SSC", "SFL", "FSCW")], "` (", roles[!roles %in% c("FSC", "SSC", "SFL", "FSCW")], ")", collapse = ", ") else "none"),
    "")

add("## 3. Values and ranges", "",
    md_table(do.call(rbind, lapply(split(ev, ev$index), function(e) data.frame(
      PnN = e$PnN[1], PnB = ref$PnB[ref$index == e$index[1]], PnR = e$PnR[1],
      `all integer` = all(e$all_integer), `min (all files)` = min(e$min), `max (all files)` = max(e$max),
      `bits needed for max` = max(e$bits_needed_for_max), `unique values (max per file)` = max(e$n_unique),
      check.names = FALSE)))), "")
bits_decl <- suppressWarnings(as.numeric(ref$PnB)); rng <- suppressWarnings(as.numeric(ref$PnR))
add(sprintf("- Storage: %s-bit fields; declared `$PnR` %s (= %s bits).", collapse(bits_decl), collapse(rng),
            collapse(round(log2(rng), 2))),
    sprintf("- Values are %s on a linear scale (`$PnE` = %s, no rescaling applied).",
            if (all(ev$all_integer)) "**integers**" else "**not all integers**", collapse(ref$PnE)), "")

add("## 4. Complete event lists or gated/subsampled?", "",
    md_table(data.frame(label = tot_by_set$label, dataset = tot_by_set$dataset, `$TOT` = tot_by_set$TOT,
                        rows = tot_by_set$rows, check.names = FALSE)), "",
    md_table(data.frame(label = sig_ev$label, dataset = sig_ev$dataset, PnN = sig_ev$PnN,
                        `% at 0` = fmt(100 * sig_ev$prop_zero), `% at PnR-1` = fmt(100 * sig_ev$prop_at_PnR_minus_1),
                        `% >= PnR` = fmt(100 * sig_ev$prop_ge_PnR), `% at observed max` = fmt(100 * sig_ev$prop_at_observed_max),
                        `% in lowest 1% of range` = fmt(sig_ev$pct_in_lowest_1pct_of_range),
                        `% in highest 1% of range` = fmt(sig_ev$pct_in_highest_1pct_of_range),
                        `unused int values in [min,max]` = fmt(sig_ev$prop_unused_integer_values_in_range),
                        check.names = FALSE)), "",
    "A distribution that tails off naturally puts well under 0.5% of events in the outermost 1% of its observed range. A hard edge (trigger threshold, saturation or a gate) puts more there.", "")
ev_flag <- function(cond, yes, no) if (cond) yes else no
add(paste0("- `$TOT` vs rows: ", ev_flag(all(tot_by_set$TOT == tot_by_set$rows), "equal in every file, so nothing was dropped between header and DATA.",
                                         "**differ** in at least one file (see table).")),
    paste0("- Pile-up at `$PnR`-1 (saturation): ", ev_flag(any(sig_ev$prop_at_PnR_minus_1 > 0.005, na.rm = TRUE),
      paste0("**>0.5% in** ", collapse(paste(sig_ev$label, sig_ev$PnN)[sig_ev$prop_at_PnR_minus_1 > 0.005 & !is.na(sig_ev$prop_at_PnR_minus_1)])),
      "none above 0.5%.")),
    paste0("- Pile-up at 0: ", ev_flag(any(sig_ev$prop_zero > 0.005),
      paste0("**>0.5% in** ", collapse(paste(sig_ev$label, sig_ev$PnN)[sig_ev$prop_zero > 0.005])), "none above 0.5%.")),
    paste0("- Hard edges (>0.5% of events in the outermost 1% of range): ", or_none(c(
      paste(sig_ev$label, sig_ev$PnN, "low end")[which(sig_ev$pct_in_lowest_1pct_of_range > 0.5)],
      paste(sig_ev$label, sig_ev$PnN, "high end")[which(sig_ev$pct_in_highest_1pct_of_range > 0.5)]), ", "), "."),
    sprintf("- Event counts: %s to %s per file.", min(tot_by_set$rows), max(tot_by_set$rows)),
    "- **Interpretation (needs human check against the plots):** a low-end hard edge on FSC or SFL is expected from the instrument trigger threshold and does not by itself mean pre-gating. Polygon pre-gating would show as empty 2D regions with straight or sharp boundaries in `figures/*_pairs.png`, which 1D statistics cannot detect.", "")

add("## 5. Do the scattergrams match Fig 2 and the Rule 1 / Rule 2 table?", "",
    "**Not assessed automatically.** This is a visual, scientific judgement on plots of real patient data, so it is left for human review (the assistant does not view rendered real-data plots).", "",
    "Open `figures/combined_key_4x3.png` next to Fig 2 of the paper and check, per row:", "",
    md_table(data.frame(file = PAPER_TABLE$label, sample = paste0("#", PAPER_TABLE$paper_sample),
                        `expected Rule 1 (aggregates: FSCW and SFL above WBCs)` = PAPER_TABLE$rule1,
                        `expected Rule 2 (mid-SFL, FSC below macrophages)` = PAPER_TABLE$rule2, check.names = FALSE)), "",
    "- Column 1 (SFL vs FSCW): for Rule 1 + files, a population above and to the right of the main WBC cloud.",
    "- Column 2 (SFL vs FSC): for Rule 2 + files, events at mid SFL sitting at lower FSC than the macrophage cluster.",
    "- Column 3 (SFL vs SSC): the usual WDF layout (lymphocytes low SSC / mid SFL, neutrophils higher SSC, monocytes/macrophages higher SFL).",
    "", "Gate-free distribution descriptors per file (median / 99th percentile):", "",
    md_table(do.call(rbind, lapply(split(sig_ev, paste(sig_ev$label, sig_ev$dataset)), function(e) {
      as.data.frame(c(list(label = e$label[1], dataset = e$dataset[1]),
                      setNames(as.list(sprintf("%s / %s", fmt(e$median), fmt(e$p99))), e$PnN)),
                    check.names = FALSE)
    }))), "")

add("## 6. Keywords hinting at the export route", "")
hint <- kw_summary[grepl(EXPORT_HINT_RE, kw_summary$keyword, perl = TRUE) | kw_summary$sysmex_specific_candidate, ]
hint <- hint[!grepl("^\\$(BEGIN|END|MODE$|DATATYPE|BYTEORD|NEXTDATA)", hint$keyword), ]
if (nrow(hint)) {
  add(md_table(data.frame(keyword = hint$keyword, `example value` = hint$example_value,
                          `non-$ (Sysmex candidate)` = hint$sysmex_specific_candidate,
                          `in all files` = hint$in_all, check.names = FALSE)), "")
} else add("No software, instrument, version or non-standard keywords found.", "")
add(sprintf("- Non-standard (non-`$`) keywords in the files: %d distinct; redacted values across all keywords: %d (see `keywords_all.csv`, column `redaction_reason`).",
            sum(kw_summary$sysmex_specific_candidate), sum(kw$redacted)), "")

add("## 7. Implications for synthetic XN FCS files", "",
    sprintf("- Write %s, one dataset per file, `$DATATYPE` %s, `$BYTEORD` %s, `$MODE` %s, delimiter ASCII %s; %s ANALYSIS segment.",
            collapse(versions), collapse(hdr$DATATYPE), collapse(hdr$BYTEORD), collapse(hdr$MODE),
            collapse(hdr$text_delimiter_ascii_code), if (any(hdr$analysis_segment_present)) "include an" else "no"),
    sprintf("- Parameters in this order: %s, with `$PnB`/`$PnR`/`$PnE` exactly as in `schema.json`.", paste0("`", ref$PnN, "`", collapse = ", ")),
    sprintf("- Draw integer values in the observed ranges; event counts for body-fluid WDF here are %s-%s per file.",
            min(tot_by_set$rows), max(tot_by_set$rows)),
    "- Reproduce the keyword set in `schema.json` (`present_in_all_files`), using masked example shapes for redacted values and fabricated values for anything identifying.",
    "- Validate generated files by running this pipeline on them: the header table, parameter table and keyword set should match these files.",
    "", "**What four body-fluid samples cannot tell you:**", "",
    paste0("- ", schema$not_inferable_from_these_files), "")

add("## Outputs", "", "`inputs_manifest.csv`, `header_structure.csv`, `keywords_all.csv`, `parameters.csv`, `event_summary.csv`, `reader_status.csv`, `schema.json`, `sessionInfo.txt`, `figures/`.")

writeLines(L, file.path(cfg$out_dir, "report.md"))
cat("  wrote report.md\n")
writeLines(capture.output(sessionInfo()), file.path(cfg$out_dir, "sessionInfo.txt"))
cat("  wrote sessionInfo.txt\n")
