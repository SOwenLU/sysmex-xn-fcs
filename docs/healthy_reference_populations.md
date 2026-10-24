# Healthy pleural-effusion reference populations: how they were derived

Log of how the population positions and proportions in `config/healthy_pe_populations.csv` were
estimated for the synthetic healthy-control generator. Started 2026-10-24; revision 2 (literature check, correlations, size-split macrophage gate) the same day.

**Every number is tagged MEASURED** (taken from the public S1–S4 events or the paper's Table 1)
**or ASSUMED** (a judgement or a literature value still to be checked). Assumed values are the ones to
challenge.

## 0. Source and scope

- **Paper:** Ai T, Tabe Y, et al. (2018) *Novel flowcytometry-based approach of malignant cell
  detection in body fluids using an automated hematology analyzer.* PLoS ONE 13(2): e0190886.
  [doi:10.1371/journal.pone.0190886](https://doi.org/10.1371/journal.pone.0190886). PDF:
  `docs/references/Ai2018_PLoSONE_0190886.pdf`. (Named "Kaku et al." elsewhere in the repo; same paper.)
- **Instrument / mode:** Sysmex XN-1000, body-fluid (XN-BF) mode, WDF channel. Four signals per
  event, 8-bit (0–255): SSC (internal structure / granularity), SFL (nucleic-acid fluorescence),
  FSC (size), FSCW (forward-scatter pulse width = time of flight, high for clumps).
- **Public files:** four supplementary FCS files, all **malignant** pleural effusions. **No
  non-malignant FCS file was published.**

  | File | Table 1 sample | Diagnosis | TNC /µL | WBC /µL | HF-BF /µL | Malignant cells (microscopy) | Events |
  |---|---|---|---|---|---|---|---|
  | S1 | #4 | adenocarcinoma | 3597 | 2526 | 1071 | 88.7% | 45,143 |
  | S2 | #13 | adenocarcinoma | 385 | 344 | 41 | 11.8% | 4,602 |
  | S3 | #16 | mesothelioma | 426 | 358 | 68 | 7.6% | 4,313 |
  | S4 | #18 | adenocarcinoma | 297 | 277 | 20 | 1.5% | 4,915 |

- **Definition of "healthy control" (decision):** a **non-malignant pleural effusion** (negative
  cytology). Truly healthy people have too little pleural fluid to sample, and normal CSF holds about
  6 cells/µL, too few events to be useful. This matches the paper's 46 non-malignant pleural effusions.

## 1. What the analyser reports in BF mode (paper, Methods)

| Sysmex category | Cell types | In WBC count? |
|---|---|---|
| PMN | neutrophils, eosinophils | yes |
| MN | lymphocytes, monocytes | yes |
| HF-BF | mesothelial cells, macrophages, malignant cells | no (reported separately, as HF-BF/µL and per 100 WBC) |

TNC = WBC + HF-BF. HF-BF is separated from WBC by an SFL cutoff whose value the paper doesn't give.
The paper's research gates are Rule 1 (clumps: high FSCW / FSC, Area 1) and Rule 2 (single cells
with SFL between WBC and HF-BF and lower FSC than macrophages, Area 2).

**Population list for synthetic data:** lymphocyte, monocyte, macrophage, neutrophil, eosinophil,
HF-BF macrophage, mesothelial, aggregate, debris. The malignant single-cell and malignant-clump
populations are **left out of the healthy baseline** and kept as injectable signatures.

## 2. Visual comparison of S1 and S4

`Rscript R/compare_s1_s4.R` → `outputs/figures/compare_S1_S4.png`. Scattergrams are coloured by % of
each file's events so the 45k vs 4.9k event counts don't dominate.

- **S1** (88.7% malignant) has heavy saturation: about 25% of events at SFL = 255 and 16% at FSC = 255,
  plus a long FSCW tail. All of this is tumour cells and clumps.
- **S4** (1.5% malignant) has little saturation, a tight FSCW range, more lymphocytes and a
  large low-SFL debris spike.
- **S4 is the reference for benign-looking structure**; S1 shows what tumour adds.

## 3. HF-BF cutoff calibrated against Table 1 (MEASURED)

`Rscript R/estimate_reference_populations.R` → `outputs/reference_populations/hfbf_cutoff_calibration.csv`

**Method.** For each file, the HF-BF share of nucleated cells is taken from Table 1:
HF / (WBC + HF). We then found the SFL value t at which the share of non-debris events (SFL ≥ 16)
with SFL ≥ t matches that share.

| File | HF-BF share (Table 1) | Calibrated SFL cutoff |
|---|---|---|
| S1 | 29.8% | 236 |
| S2 | 10.7% | 223 |
| S3 | 16.0% | 200 |
| S4 | 6.7% | 205 |

- **Result:** the four files agree on a **cutoff of about SFL 214** (median; range 200–236).
- **Consequence:** the diagonal band at SFL ~80–200 (monocytes and most macrophages) is **counted as
  WBC (MN) by the analyser, not as HF-BF**. Only cells near SFL saturation count as HF-BF.

## 4. Gating, positions and shapes (MEASURED)

Same script → `outputs/reference_populations/gate_summary.csv` (shares and percentiles) and
`gate_shape.csv` (centre, robust SD, pairwise correlations). The gates are rectangles applied in
order; an event takes the first gate it matches.

| Order | Gate | Rule |
|---|---|---|
| 1 | debris | SFL < 16 (same rule as `R/wdf_populations.R`) |
| 2 | aggregate | FSC = 255 or FSCW ≥ 60 |
| 3 | HF-BF | SFL ≥ 214 (from step 3) |
| 4 | lymphocyte | SSC < 95 and SFL < 80 |
| 5 | neutrophil | SSC ≥ 140, SFL < 50 and FSC ≥ 60 (FSC keeps out the S4 small cluster) |
| 6 | monocyte | SSC ≥ 80, SFL ≥ 50 and FSC < 80 |
| 7 | macrophage | SSC ≥ 80, SFL ≥ 50 and FSC ≥ 80 |

**Revision 2 (2026-10-24).** The first version used a monocyte gate of 80 ≤ SSC < 160 and a separate
macrophage band at SSC ≥ 160. That clipped the macrophage SSC SD to 8, and the synthetic test showed
a vertical stripe. The SFL 50–214 band is now split **by size (FSC 80)**, because on SFL vs FSC the
monocytes form a narrow column at FSC ~50 and the macrophages a broad cloud at FSC 80–250.

- **Spread:** SD = (P84 − P16) / 2. This equals the SD for a normal distribution and resists outliers.
- **Correlation:** Spearman's ρ converted to Pearson, r = 2 sin(πρ/6).

Per-gate medians:

| Gate | File | SSC | SFL | FSC | FSCW | % of cells |
|---|---|---|---|---|---|---|
| lymphocyte | S1 / S2 / S4 | 73 / 71 / 69 | 52 / 52 / 41 | 49 / 47 / 44 | 17 / 17 / 16 | 22 / 38 / 26 |
| neutrophil | S1 / S2 / S3 / S4 | 158 / 156 / 152 / 179 | 36 / 39 / 40 / 34 | 91 / 85 / 92 / 93 | 22 | 1.6 / 3.3 / 2.7 / 5.4 |
| monocyte | S1 / S2 / S4 | 139 / 124 / 125 | 156 / 111 / 119 | 48 / 55 / 52 | 21 / 21 / 20 | 26 / 33 / 33 |
| macrophage | S1 / S2 / S4 | 154 / 136 / 148 | 127 / 98 / 120 | 137 / 97 / 122 | 35 / 30 / 34 | 9.9 / 7.2 / 19.3 |
| HF-BF | S1 / S2 / S4 | 165 / 170 / 167 | 255 | 66 / 111 / 70 | 29 / 30 / 29 | 18 / 7.5 / 5.1 |
| aggregate | S1 / S2 / S4 | 212 / 217 / 190 | 255 / 255 / 237 | 255 | 77 / 70 / 62 | 19 / 4.5 / 1.8 |
| debris | S1 / S2 / S4 | 60 / 68 / 69 | 3 / 5 / 3 | 17 / 18 / 19 | 9 | 3.2 / 10.7 / 33.2 (% of all events) |

**The correlations are strong and consistent across files.** FSC–FSCW is 0.5–0.9 in every population.
In the diagonal band, SSC–SFL is 0.4–0.7. In macrophages, SFL–FSC is about 0.67. Leaving these out is
what made the first synthetic test look like separate blobs.

**Checks on events that looked odd in S4:**

- **S4 runs about 10 SFL lower** than S1 and S2 (lymphocyte SFL 41 vs 52), and its lymphocytes are
  wider. Lymphocyte positions are therefore anchored on S1 and S2. The offset is evidence for a
  batch-shift term in the noise model.
- **S4's 33% debris is overstated:** 21% of its SFL < 16 events have FSC ≥ 35, so the gate catches
  weakly stained cells.
- **S4 small low-SFL cluster** (SSC ~113, SFL ~29, FSC ~40): smaller than lymphocytes. Dropped
  (step 9).
- **S4's neutrophils centre at SSC 179, against 152–158 in S1–S3.** That may be eosinophils, so the
  eosinophil position is placed there (ASSUMED).

## 5. Final positions (`config/healthy_pe_populations.csv`)

The config carries a centre and SD per signal plus the six pairwise correlations. Centres above 255
(SFL in HF-BF and aggregates) are latent values, clipped at 255.

| Population | Sysmex | SSC | SFL | FSC | FSCW | Key correlations | Position from |
|---|---|---|---|---|---|---|---|
| lymphocyte | MN | 72 ± 9 | 52 ± 12 | 48 ± 8 | 17 ± 1.5 | FSC–FSCW 0.66 | MEASURED: S1 + S2 |
| monocyte | MN | 125 ± 14 | 115 ± 38 | 53 ± 12 | 20 ± 4 | SSC–SFL 0.50 | MEASURED: S2 + S4 |
| macrophage | MN | 148 ± 16 | 120 ± 39 | 122 ± 42 | 34 ± 4.5 | all 0.55–0.69 | MEASURED: S4 |
| neutrophil | PMN | 154 ± 9.5 | 39 ± 5 | 88 ± 16 | 22 ± 2 | FSC–FSCW 0.65 | MEASURED: S2 + S3 |
| eosinophil | PMN | 180 ± 12 | 40 ± 6 | 93 ± 17 | 23 ± 2 | as neutrophil | **ASSUMED** (S4 high-SSC end) |
| HF-BF macrophage | HF-BF | 167 ± 18 | 262 ± 20 (latent) | 80 ± 35 | 29 ± 7.5 | FSC–FSCW 0.82 | MEASURED: S4 |
| mesothelial | HF-BF | same as HF-BF macrophage | | | | | MEASURED region; not separable |
| aggregate | HF-BF | 205 ± 28 | 262 ± 20 (latent) | 255 (fixed) | 65 ± 25 | SSC–FSCW 0.60 | MEASURED: S2–S4 |
| debris | – | 66 ± 30 | 0–15 (half at 0) | 18 ± 12 | 9 ± 5.5 | FSC–FSCW 0.88 | MEASURED: S1–S4 |

Overlay: `Rscript R/plot_reference_populations.R` → `outputs/reference_populations/populations_overlay.png`
(centre ± 2 SD ellipses, tilted by the correlation, over S4 and S1).

## 6. Proportions

### 6a. Anchored on the paper (MEASURED)

From the 46 non-malignant pleural effusions in Table 1:

| Quantity | Value | How |
|---|---|---|
| TNC | median 1011 /µL (range 36–7037) | Table 1 |
| HF-BF per 100 WBC | median 6.3 (IQR 2.2–12.4, range 0.2–26.2) | Table 1 |
| **HF-BF share of nucleated cells** | **median 5.9% (IQR 2.1–11.0%)** | x / (100 + x) |
| Benign samples flagged by Rule 1 or 2 | 8 of 65 (12%) | specificity 87.7%; samples #28–35 |
| Events per file | **≈ 12 × TNC** (10–17 across S1–S4) | events ÷ TNC: 12.6, 12.0, 10.1, 16.5 |

→ A typical healthy file has **about 12,000 events**.

### 6b. Literature check (revision 2)

| Source | Population | Finding |
|---|---|---|
| [Noppen et al. 2000, *Am J Respir Crit Care Med*](https://www.wikigenes.org/e/ref/e/10988124.html) (PMID 10988124) | pleural lavage, healthy non-smokers | macrophages **75%** (IQR 16), lymphocytes **23%** (IQR 18), mesothelial **1%** (IQR 2), neutrophils **0%** (IQR 1), eosinophils **0%**; about 1,716 cells/µL |
| [Ferreiro et al. 2017, *Rev Clin Esp* 217:136–43](https://revclinesp.es/en-behavior-nucleated-cells-in-various-articulo-S2254887417300097) | 1,467 effusions, 354 heart failure | only **44%** of heart-failure effusions were lymphocyte-predominant; the leading causes of lymphocytic effusions were TB and cancer |
| [Lymphocyte-predominant exudates review](https://shc.amegroups.org/article/view/7225/html) | review | lymphocytes > 50% = lymphocyte-predominant, which suggests a chronic process; neutrophils point to an acute one |
| [Fleming et al. 2012, *Clin Chem Lab Med*](https://www.degruyterbrill.com/document/doi/10.1515/cclm-2011-0927/html) | XN-1000 BF mode vs microscopy | the XN counts more PMN than microscopy (y = 1.48x) |

**What changed.** Revision 1 assumed a lymphocyte-predominant profile (50% lymphocytes, 13% macrophages).
The literature points the other way. Normal fluid is mostly macrophages, and even heart-failure
effusions are lymphocyte-predominant in fewer than half of cases. The defaults now sit between
Noppen's normal fluid and a typical benign effusion. They also match S4 (the least malignant file)
reasonably: 26% lymphocytes, 33% monocytes, 19% macrophages, 5% neutrophils.

### 6c. Composition for synthetic files

| Population | % of nucleated cells (default) | Range | Basis |
|---|---|---|---|
| lymphocyte | 40 | 20–60 | between Noppen 23% and lymphocyte-predominant effusions |
| monocyte | 13 | 5–20 | ASSUMED |
| macrophage (MN) | 30 | 15–50 | Noppen 75% macrophages; most count as MN since HF-BF is only ~6% |
| neutrophil | 8 | 1–25 | Noppen ~0%; benign effusions vary, and the XN over-counts PMN |
| eosinophil | 2 | 0–10 | Noppen ~0%; ≥ 10% = eosinophilic effusion |
| HF-BF macrophage | 4 | 1–8 | HF-BF total 6% (MEASURED, Table 1); 2:1 split ASSUMED |
| mesothelial | 2 | 0.5–5 | Noppen 1%; as above |
| aggregate | 1 | 0–2 | keeps the 12% benign Rule 1 hit rate possible |
| **Total** | **100** | | |
| debris | **8% of all events** | 3–15% | S1 3.2%, S2 10.7%, S3 3.7% (S4 excluded) |

## 7. Synthetic test

`Rscript R/simulate_healthy_test.R` → `outputs/reference_populations/synthetic_test.png`.
This draws one 12,000-event file (seed 1) from the config, one multivariate normal per population,
and plots it beside S4. There is no sample-to-sample variation yet.

**Revision 1** drew each channel independently and gave separate blobs, a vertical macrophage stripe
and a wide FSC–FSCW column. **Revision 2** adds the correlations and the size-split macrophage gate.
Result:

- **SSC vs SFL:** a continuous diagonal band from monocytes to macrophages to HF-BF, as in S4.
- **FSC vs FSCW:** the real diagonal shape, with aggregates along FSC = 255.
- **SFL vs FSC:** a monocyte column at FSC ~50 and a macrophage cloud along the diagonal, as in S4.
- **Differs from S4 by design:** more lymphocytes and macrophages and fewer monocytes (literature
  composition); tighter lymphocytes (anchored on S1 and S2, not S4's weak stain); less debris (8%).

Remaining known simplifications: debris SFL uses a fixed zero-inflated tail, and the eosinophil
position is assumed.

## 8. Decisions

- **Healthy control = non-malignant pleural effusion** (2026-10-24).
- **S4 low-FSC cluster** (SSC ~113, SFL ~29, FSC ~40): **dropped** from the healthy baseline
  (2026-10-24). It's treated as degenerate cells or debris.
- **Monocyte and macrophage split by FSC 80** (revision 2, 2026-10-24).
- **Composition revised to the literature** (revision 2, 2026-10-24).

## 9. Open questions for review

1. **Composition:** is a 40% lymphocyte / 43% monocyte-and-macrophage default right for the cohort
   we're mimicking? For truly normal fluid, use Noppen (about 75% macrophage-lineage).
2. **Eosinophil position:** assumed at S4's high-SSC end of the neutrophil gate.
3. **HF-BF macrophage vs mesothelial:** they share one WDF region; the 2:1 split is arbitrary.

## Files

| File | What |
|---|---|
| `R/compare_s1_s4.R` | S1 vs S4 figure (step 2) |
| `R/estimate_reference_populations.R` | HF-BF calibration, gate shares, shapes and correlations (steps 3–4) |
| `R/plot_reference_populations.R` | overlay of the config on S4/S1 (step 5) |
| `R/simulate_healthy_test.R` | one synthetic healthy file vs S4 (step 7) |
| `config/healthy_pe_populations.csv` | the population table (steps 5–6) |
| `outputs/reference_populations/` | calibration, gate summary and gate shape CSVs; overlay and synthetic-test PNGs |
