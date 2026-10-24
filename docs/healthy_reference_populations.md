# Healthy pleural-effusion reference populations: how they were derived

Log of how the population positions and proportions in `config/healthy_pe_populations.csv` were
estimated for the synthetic healthy-control generator. Started 2026-10-24.

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

## 4. Gating and per-population positions (MEASURED)

Same script → `outputs/reference_populations/gate_summary.csv`. The gates are rectangles read off the
step 2 figure and are applied in order; an event takes the first gate it matches.

| Order | Gate | Rule |
|---|---|---|
| 1 | debris | SFL < 16 (same rule as `R/wdf_populations.R`) |
| 2 | aggregate | FSC = 255 or FSCW ≥ 60 |
| 3 | HF-BF band | SFL ≥ 214 (from step 3) |
| 4 | lymphocyte | SSC < 95 and SFL < 80 |
| 5 | neutrophil | SSC ≥ 140 and SFL < 50 |
| 6 | monocyte (+ macrophage) | 80 ≤ SSC < 160 and SFL ≥ 50 |

Medians per gate (P10–P90 in the CSV):

| Gate | File | SSC | SFL | FSC | FSCW | % of cells |
|---|---|---|---|---|---|---|
| lymphocyte | S1 / S2 / S4 | 73 / 71 / 69 | 52 / 52 / 41 | 49 / 47 / 44 | 17 / 17 / 16 | 22 / 38 / 26 |
| neutrophil | S1 / S2 / S4 | 155 / 155 / 178 | 36 / 38 / 34 | 89 / 82 / 89 | 22 / 22 / 23 | 1.8 / 3.7 / 6.2 |
| monocyte (+ macrophage) | S1 / S2 / S4 | 139 / 124 / 129 | 148 / 107 / 118 | 51 / 57 / 59 | 22 / 22 / 23 | 31 / 38 / 47 |
| HF-BF band | S1 / S2 / S4 | 165 / 170 / 167 | 255 / 255 / 255 | 66 / 111 / 70 | 29 / 30 / 29 | 18 / 7.5 / 5.1 |
| aggregate | S1 / S2 / S4 | 212 / 217 / 190 | 255 / 255 / 237 | 255 | 77 / 70 / 62 | 19 / 4.5 / 1.8 |
| debris | S1 / S2 / S4 | 60 / 68 / 69 | 3 / 5 / 3 | 17 / 18 / 19 | 9 | 3.2 / 10.7 / 33.2 (% of all events) |

**Checks on events that looked odd in S4:**

- **S4 runs about 10 SFL lower** than S1 and S2 (lymphocyte SFL 41 vs 52) and its lymphocytes are
  wider (MAD 16 vs 10). This suggests weaker staining or run-to-run variation. Positions are anchored
  on S1 and S2 for lymphocytes, and the offset is kept as evidence for a batch-shift term in the
  noise model.
- **S4's 33% debris is overstated.** 21% of its SFL < 16 events have FSC ≥ 35 and 28% have SFL 8–15,
  so the gate is cutting into weakly stained cells. The healthy debris fraction is therefore not
  taken from S4.
- **S4 has a high-SSC band below the HF-BF cutoff** (SSC ≥ 160, SFL 80–214; n = 148): median SSC 167,
  SFL 142, FSC 164, FSCW 38. These are large, structured, moderately fluorescent cells, which fits
  **macrophages** that the analyser counts as MN. This is the macrophage row in the config.
- **S4 has an unidentified low-FSC cluster** (SSC 99–135, SFL 16–50; n = 276): median SSC 113,
  SFL 29, **FSC 40** (smaller than lymphocytes). It's too small to be intact neutrophils (FSC ~86).
  Most likely degenerate cells or debris. **Left out of the baseline; needs review (see step 7).**
- **S4's neutrophil gate centres at SSC 178, against 155 in S1 and S2.** S4 may contain eosinophils,
  which sit at higher SSC. Eosinophils aren't separable in these files, so the eosinophil position is
  **ASSUMED** at SSC 180 / SFL 45, just above the neutrophils.

## 5. Final positions (`config/healthy_pe_populations.csv`)

The **centre** is the gate median; **SD ≈ (P90 − P10) / 2.56** (the P10–P90 width of a normal
distribution). Centres above 255 (SFL in HF-BF and aggregates) are latent values clipped at 255,
the same approach as `R/wdf_populations.R`.

| Population | Sysmex | SSC | SFL | FSC | FSCW | Position |
|---|---|---|---|---|---|---|
| lymphocyte | MN | 71 ± 9 | 50 ± 12 | 47 ± 9 | 17 ± 2 | MEASURED (S1+S2) |
| monocyte | MN | 127 ± 13 | 110 ± 30 | 58 ± 15 | 22 ± 5 | MEASURED (S2+S4); gate also contains macrophages |
| macrophage | MN | 167 ± 8 | 142 ± 34 | 165 ± 58 | 38 ± 6 | MEASURED (S4 high-SSC band) |
| neutrophil | PMN | 155 ± 10 | 37 ± 7 | 86 ± 20 | 22 ± 3 | MEASURED (S1+S2+S4) |
| eosinophil | PMN | 180 ± 10 | 45 ± 8 | 90 ± 20 | 22 ± 3 | **ASSUMED** |
| HF-BF macrophage | HF-BF | 167 ± 18 | 255 ± 25 (latent) | 70 ± 46 | 29 ± 9 | MEASURED (S2+S4 HF-BF band) |
| mesothelial | HF-BF | same region as HF-BF macrophage | | | | MEASURED region; not separable on WDF |
| aggregate | HF-BF | 200 ± 30 | 245 ± 20 (latent) | 255 (fixed) | 65 ± 20 | MEASURED (S2+S3+S4) |
| debris | – | 65 ± 25 | 3 (zero-inflated) | 18 ± 14 | 9 ± 5 | MEASURED (S1+S2+S3) |

Overlay: `Rscript R/plot_reference_populations.R` → `outputs/reference_populations/populations_overlay.png`
(centre ± 2 SD ellipses on S4 and S1).

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

→ A typical healthy file has **about 12,000 events** (TNC ~1000/µL). The range from the TNC spread
is about 450 to 90,000 events.

### 6b. Split within white cells (ASSUMED, literature to confirm)

The paper doesn't report the lymphocyte / neutrophil / monocyte split. The values below are a
benign-effusion profile (lymphocyte-predominant, some macrophages, few neutrophils and eosinophils),
with HF-BF fixed by 6a.

| Population | % of nucleated cells (default) | Range | Basis |
|---|---|---|---|
| lymphocyte | 50 | 30–65 | ASSUMED: benign effusions are commonly lymphocyte-predominant |
| monocyte | 15 | 8–25 | ASSUMED |
| macrophage (MN) | 13 | 5–25 | ASSUMED; S4 shows a clear macrophage band |
| neutrophil | 12 | 3–25 | ASSUMED; above ~25–50% suggests parapneumonic/inflammatory |
| eosinophil | 3 | 0–8 | ASSUMED; ≥ 10% defines an eosinophilic effusion |
| HF-BF macrophage | 4 | 1–8 | Table 1 HF-BF share 6% (MEASURED), split 2:1 (ASSUMED) |
| mesothelial | 2 | 0.5–4 | as above |
| aggregate | 1 | 0–2 | ASSUMED; keeps the ~12% benign Rule 1 hit rate possible |
| **Total** | **100** | | |
| debris | **8% of all events** | 3–15% | S1 3.2%, S2 10.7%, S3 3.7% (S4 excluded: overstated) |

**Alternative "truly normal" profile (to verify):** Noppen et al. 2000 (*Am J Respir Crit Care Med*
162:1023–6) used pleural lavage in healthy volunteers and reported roughly 75% macrophages,
23% lymphocytes, ~1–2% mesothelial cells and ≤ 2% neutrophils and eosinophils. These figures are
quoted from memory and must be checked against the paper before use. If that profile is preferred,
move most of the lymphocyte share into monocyte/macrophage.

## 7. Synthetic test (one file)

`Rscript R/simulate_healthy_test.R` → `outputs/reference_populations/synthetic_test.png`.
This draws 12,000 events (seed 1) from the config, with 8% debris, and plots them beside S4.
The test is deliberately crude: each channel is drawn independently and there is no sample-to-sample
variation.

**What matches S4:** the lymphocyte, neutrophil, monocyte and debris positions; the SFL = 255 HF-BF
ceiling; a small FSC = 255 aggregate edge.

**What doesn't, and the fix for the real generator:**

1. **Real populations form a continuous diagonal band on SSC vs SFL; the synthetic ones are separate
   blobs.** Fix: draw each population with its gate covariance, not independent channels.
2. **The macrophage population is a vertical stripe** at SSC 167. Its SSC SD (8) is too narrow, and
   in real data it runs along the diagonal. This is the same fix as 1.
3. **FSC and FSCW are correlated in real data** (diagonal in the Rule 1 view); the synthetic data
   is a wide column. This is the same fix as 1.
4. **HF-BF and macrophage FSC SDs are too wide.** Synthetic events spread across FSC 10–250, while S4
   keeps most HF-BF cells at FSC 40–100. Fix: narrow the SDs, or use a skewed distribution.

`R/wdf_populations.R` already fits per-cluster covariance, so fixes 1–3 can reuse it.

## 8. Decisions

- **S4 low-FSC cluster** (SSC ~113, SFL ~29, FSC ~40): **dropped** from the healthy baseline
  (decision 2026-10-24). It's treated as degenerate cells or debris and not modelled.

## 9. Open questions for review

1. **The white-cell split (6b):** check against a benign-effusion reference and choose between the
   benign-effusion and truly-normal profiles.
2. **Eosinophil position:** assumed. Is S4's neutrophil gate at SSC 178 actually eosinophils?
3. **HF-BF macrophage vs mesothelial:** they share one WDF region; the 2:1 split is arbitrary.
4. **Monocyte vs macrophage boundary:** the monocyte gate takes in some macrophages, so the
   monocyte SFL SD (30) is probably too wide.

## Files

| File | What |
|---|---|
| `R/compare_s1_s4.R` | S1 vs S4 figure (step 2) |
| `R/estimate_reference_populations.R` | HF-BF calibration and gate statistics (steps 3–4) |
| `R/plot_reference_populations.R` | overlay of the config on S4/S1 (step 5) |
| `R/simulate_healthy_test.R` | one synthetic healthy file vs S4 (step 7) |
| `config/healthy_pe_populations.csv` | the population table (steps 5–6) |
| `outputs/reference_populations/` | calibration CSV, gate summary CSV, overlay PNG |
