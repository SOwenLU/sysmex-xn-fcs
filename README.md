# Sysmex XN FCS characterisation

Characterises the four supplementary FCS files from Kaku et al. 2018 (PLOS ONE,
doi:10.1371/journal.pone.0190886; Sysmex XN-1000, XN-BF mode, WDF channel) to define a
schema for synthetic XN data.

## Run

```sh
Rscript run_all.R <fcs_folder> [output_folder] [--map S1=<file>,S2=<file>,S3=<file>,S4=<file>] [--export-events]
```

- `<fcs_folder>` is read-only. Every file in it is checked; FCS files are identified by their
  first 6 bytes (`FCS2.0`/`FCS3.0`/`FCS3.1`), not their extension. Other files are skipped with a warning.
- Files are mapped to S1-S4 from `s001`..`s004` / `S1`..`S4` in the name. If that is ambiguous
  the run stops, lists the files and sizes, and asks for `--map`.
- Outputs go to `./outputs` unless `output_folder` is given.
- `--export-events` also writes one CSV per dataset with every event's raw (untransformed) channel
  values: `events/<label>_ds<n>_events.csv`, columns `event` then one per `$PnN`.

Requirements: R >= 4.4 with flowCore, ggplot2, cowplot, jsonlite, digest; Python 3 (stdlib only).
Set `FCS_PYTHON` to use a different Python interpreter.

## Steps

| Script | Does | Writes |
|---|---|---|
| `R/01_inspect_header.R` | find + hash files, map to S1-S4, byte-level HEADER/TEXT/DATA structure | `inputs_manifest.csv`, `header_structure.csv` |
| `R/02_read_and_summarise.R` | `read.FCS(transformation = FALSE, truncate_max_range = FALSE, emptyValue = FALSE)` per dataset, cross-check against the raw parser, redact identifiers | `keywords_all.csv`, `parameters.csv`, `event_summary.csv`, `reader_status.csv`, `events/*.csv` (opt-in) |
| `R/03_plots.R` | linear density plots and histograms, identical axes across files | `figures/*.png`, `figures/combined_key_4x3.png` |
| `R/04_schema_report.R` | generator spec and write-up | `schema.json`, `report.md`, `sessionInfo.txt` |

`py/fcs_raw_parse.py` is an independent byte-level parser (HEADER offsets, delimiter, `$NEXTDATA`
chain, ANALYSIS/STEXT, per-parameter aggregates and DATA checksum). It prints JSON to stdout only;
keyword values are redacted in R before anything is written. If flowCore fails on a file, the error
is logged in `reader_status.csv` and events are read with a manual R reader from the raw-parser offsets.

Shared code: `R/paths.R` (command-line paths, paper table), `R/helpers.R`.

## Privacy

Values of keywords that look like patient/sample/operator identifiers or dates are replaced with
`[REDACTED; shape=...]` (digits → 9, letters → X), and `redaction_reason` gives the rule that matched.
Only aggregate statistics are written by default. Event-level data is saved only with
`--export-events`; those files hold channel values and an event number, never keyword values.

## Testing

```sh
Rscript tests/make_synthetic_fixture.R <scratch_folder>/fixture
Rscript run_all.R <scratch_folder>/fixture <scratch_folder>/fixture_out
```

The fixture is fully fabricated. It has four FCS3.0 files with PLOS-style names and no extension
(s004 holds two datasets), fake identifier and date keywords, and one non-FCS file.
