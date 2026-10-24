# Sysmex XN-1000 FCS characterisation (Kaku et al. 2018, S1-S4)

Generated 2026-10-23 09:56 from `4` FCS file(s); 0 non-FCS file(s) skipped. All numbers come from the CSVs in this folder.

## Inputs

| label | file | bytes | sha256 | paper_sample | diagnosis | rule1 | rule2 |
|---|---|---|---|---|---|---|---|
| S1 | synthetic.s001.fcs | 181303 | 853c1ee2b20b2c35 | 4 | adenocarcinoma | + | + |
| S2 | synthetic.s002.fcs | 19138 | 02d5736627cd5c07 | 13 | adenocarcinoma | + | - |
| S3 | synthetic.s003.fcs | 17982 | fb6b9a45d471d0a4 | 16 | mesothelioma | - | + |
| S4 | synthetic.s004.fcs | 20390 | c318a9db541873ac | 18 | adenocarcinoma | - | - |

Full SHA-256 in `inputs_manifest.csv`. Mapping source: filename.

## 1. File structure

- **FCS version:** FCS3.0
- **Datasets per file:** 1 (`$NEXTDATA` = 0)
- **HEADER:** TEXT starts at byte 58; DATA offsets in HEADER and `$BEGINDATA/$ENDDATA` agree: TRUE; extra OTHER segments: 0
- **TEXT delimiter:** `/` (ASCII 47); TEXT ends with a delimiter: TRUE; 42 keywords per file
- **Encoding:** `$DATATYPE`=I, `$BYTEORD`=1,2,3,4, `$MODE`=L, 4 bytes per event
- **ANALYSIS segment:** absent; supplemental TEXT: absent; trailing CRC-like bytes: no
- **Readers:** flowCore. flowCore errors: none. flowCore warnings: none.
- **Cross-check:** flowCore and the independent Python byte parser agree on n/min/max/mean/unique for 16 of 16 file x parameter rows; TEXT values match for 168 of 168 keywords present in both.

## 2. Parameters

Parameter set identical across all files: **TRUE**.

| n | PnN | PnS | PnB | PnR | PnE | PnG | mapped role |
|---|---|---|---|---|---|---|---|
| 1 | SSC | Side Scatter Signal | 8 | 256 | 0,0 | (absent) | SSC |
| 2 | SFL | Side Fluorescence Signal | 8 | 256 | 0,0 | (absent) | SFL |
| 3 | FSC | Forward Scatter Signal | 8 | 256 | 0,0 | (absent) | FSC |
| 4 | FSCW | Forward Scatter Pulse Width Signal | 8 | 256 | 0,0 | (absent) | FSCW |

- WDF signals identified by name: SSC → `SSC`, SFL → `SFL`, FSC → `FSC`, FSCW → `FSCW`.
- Missing WDF roles: none.
- Extra parameters (time, IDs, flags, cluster labels, unmapped): none.

## 3. Values and ranges

| PnN | PnB | PnR | all integer | min (all files) | max (all files) | bits needed for max | unique values (max per file) |
|---|---|---|---|---|---|---|---|
| SSC | 8 | 256 | TRUE | 6 | 255 | 8 | 248 |
| SFL | 8 | 256 | TRUE | 0 | 255 | 8 | 256 |
| FSC | 8 | 256 | TRUE | 10 | 255 | 8 | 246 |
| FSCW | 8 | 256 | TRUE | 0 | 236 | 8 | 215 |

- Storage: 8-bit fields; declared `$PnR` 256 (= 8 bits).
- Values are **integers** on a linear scale (`$PnE` = 0,0, no rescaling applied).

## 4. Complete event lists or gated/subsampled?

| label | dataset | $TOT | rows |
|---|---|---|---|
| S1 | 1 | 45143 | 45143 |
| S2 | 1 | 4602 | 4602 |
| S3 | 1 | 4313 | 4313 |
| S4 | 1 | 4915 | 4915 |

| label | dataset | PnN | % at 0 | % at PnR-1 | % >= PnR | % at observed max | % in lowest 1% of range | % in highest 1% of range | unused int values in [min,max] |
|---|---|---|---|---|---|---|---|---|---|
| S1 | 1 | SSC |    0 | 1.61 |    0 | 1.61 | 0.00665 | 1.79 | 0.008 |
| S1 | 1 | SFL | 0.775 | 25.5 |    0 | 25.5 | 1.36 | 25.7 |    0 |
| S1 | 1 | FSC |    0 | 16.6 |    0 | 16.6 | 0.603 | 16.6 |    0 |
| S1 | 1 | FSCW | 0.312 |    0 |    0 | 0.00222 | 0.412 | 0.00222 | 0.0928 |
| S2 | 1 | SSC |    0 | 0.435 |    0 | 0.435 | 0.0652 |  0.5 | 0.0208 |
| S2 | 1 | SFL | 2.46 | 8.65 |    0 | 8.65 | 3.91 | 8.67 | 0.0273 |
| S2 | 1 | FSC |    0 | 3.06 |    0 | 3.06 | 1.72 | 3.06 | 0.106 |
| S2 | 1 | FSCW | 0.152 |    0 |    0 | 0.0217 | 0.196 | 0.0217 | 0.288 |
| S3 | 1 | SSC |    0 | 0.301 |    0 | 0.301 | 0.162 | 0.301 | 0.0972 |
| S3 | 1 | SFL | 2.83 | 5.17 |    0 | 5.17 | 3.18 | 5.31 | 0.043 |
| S3 | 1 | FSC |    0 | 1.11 |    0 | 1.11 | 0.301 | 1.11 | 0.142 |
| S3 | 1 | FSCW |    0 |    0 |    0 | 0.0232 | 0.255 | 0.0232 | 0.377 |
| S4 | 1 | SSC |    0 | 0.061 |    0 | 0.061 | 0.0407 | 0.102 | 0.0921 |
| S4 | 1 | SFL | 9.26 | 3.09 |    0 | 3.09 | 14.4 | 3.11 | 0.0703 |
| S4 | 1 | FSC |    0 | 0.875 |    0 | 0.875 | 2.93 | 0.875 | 0.102 |
| S4 | 1 | FSCW | 0.0814 |    0 |    0 | 0.0407 | 0.0814 | 0.0407 | 0.182 |

A distribution that tails off naturally puts well under 0.5% of events in the outermost 1% of its observed range. A hard edge (trigger threshold, saturation or a gate) puts more there.

- `$TOT` vs rows: equal in every file, so nothing was dropped between header and DATA.
- Pile-up at `$PnR`-1 (saturation): **>0.5% in** S1 SSC, S1 SFL, S1 FSC, S2 SFL, S2 FSC, S3 SFL, S3 FSC, S4 SFL, S4 FSC
- Pile-up at 0: **>0.5% in** S1 SFL, S2 SFL, S3 SFL, S4 SFL
- Hard edges (>0.5% of events in the outermost 1% of range): S1 SFL low end, S1 FSC low end, S2 SFL low end, S2 FSC low end, S3 SFL low end, S4 SFL low end, S4 FSC low end, S1 SSC high end, S1 SFL high end, S1 FSC high end, S2 SFL high end, S2 FSC high end, S3 SFL high end, S3 FSC high end, S4 SFL high end, S4 FSC high end.
- Event counts: 4313 to 45143 per file.
- **Interpretation (needs human check against the plots):** a low-end hard edge on FSC or SFL is expected from the instrument trigger threshold and does not by itself mean pre-gating. Polygon pre-gating would show as empty 2D regions with straight or sharp boundaries in `figures/*_pairs.png`, which 1D statistics cannot detect.

## 5. Do the scattergrams match Fig 2 and the Rule 1 / Rule 2 table?

**Not assessed automatically.** This is a visual, scientific judgement on plots of real patient data, so it is left for human review (the assistant does not view rendered real-data plots).

Open `figures/combined_key_4x3.png` next to Fig 2 of the paper and check, per row:

| file | sample | expected Rule 1 (aggregates: FSCW and SFL above WBCs) | expected Rule 2 (mid-SFL, FSC below macrophages) |
|---|---|---|---|
| S1 | #4 | + | + |
| S2 | #13 | + | - |
| S3 | #16 | - | + |
| S4 | #18 | - | - |

- Column 1 (SFL vs FSCW): for Rule 1 + files, a population above and to the right of the main WBC cloud.
- Column 2 (SFL vs FSC): for Rule 2 + files, events at mid SFL sitting at lower FSC than the macrophage cluster.
- Column 3 (SFL vs SSC): the usual WDF layout (lymphocytes low SSC / mid SFL, neutrophils higher SSC, monocytes/macrophages higher SFL).

Gate-free distribution descriptors per file (median / 99th percentile):

| label | dataset | SSC | SFL | FSC | FSCW |
|---|---|---|---|---|---|
| S1 | 1 |  147 /  255 |  160 /  255 |   58 /  255 |   23 /  150 |
| S2 | 1 |  106 /  237 |   73 /  255 |   52 /  255 |   19 /   97 |
| S3 | 1 |  146 /  221 |  141 /  255 |   76 /  255 |   24 /   42 |
| S4 | 1 |  108 /  214 |   42 /  255 |   45 /  243 |   18 /   58 |

## 6. Keywords hinting at the export route

| keyword | example value | non-$ (Sysmex candidate) | in all files |
|---|---|---|---|
| $CYT | XN-20 | FALSE | TRUE |
| $CYTSN | 90001 | FALSE | TRUE |
| $SYS | Windows 7 | FALSE | TRUE |

- Non-standard (non-`$`) keywords in the files: 0 distinct; redacted values across all keywords: 28 (see `keywords_all.csv`, column `redaction_reason`).

## 7. Implications for synthetic XN FCS files

- Write FCS3.0, one dataset per file, `$DATATYPE` I, `$BYTEORD` 1,2,3,4, `$MODE` L, delimiter ASCII 47; no ANALYSIS segment.
- Parameters in this order: `SSC`, `SFL`, `FSC`, `FSCW`, with `$PnB`/`$PnR`/`$PnE` exactly as in `schema.json`.
- Draw integer values in the observed ranges; event counts for body-fluid WDF here are 4313-45143 per file.
- Reproduce the keyword set in `schema.json` (`present_in_all_files`), using masked example shapes for redacted values and fabricated values for anything identifying.
- Validate generated files by running this pipeline on them: the header table, parameter table and keyword set should match these files.

**What four body-fluid samples cannot tell you:**

- Whole-blood (XN WB mode) event counts and WDF cluster positions
- Other XN channels: WNR, WPC, RET, PLT-F, PLT-I/RBC (impedance)
- Normal or non-malignant body-fluid scattergrams (all four are malignant pleural effusions)
- Day-to-day / instrument-to-instrument calibration differences
- Whether a different export route (e.g. other IPU/service software version) changes keywords or encoding

## Outputs

`inputs_manifest.csv`, `header_structure.csv`, `keywords_all.csv`, `parameters.csv`, `event_summary.csv`, `reader_status.csv`, `schema.json`, `sessionInfo.txt`, `figures/`.
