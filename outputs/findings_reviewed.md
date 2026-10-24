# Kaku et al. 2018 XN FCS files (S1–S4): findings

Reviewed write-up of the pipeline outputs, including a visual read of the figures. The auto-generated `report.md` is rebuilt on every run; this file is not.

The pipeline read all four files with no errors or warnings. flowCore and the independent byte parser agreed on all 16 file × parameter checks and all 168 keyword values. The non-FCS file in the folder (`Brief.txt`) was skipped.

## 1. File structure
- **Format:** FCS3.0 with one dataset per file (`$NEXTDATA` = 0). There's no ANALYSIS segment, no supplemental TEXT and no trailing CRC.
- **HEADER:** TEXT starts at byte 58. The offsets in the HEADER match `$BEGINDATA`/`$ENDDATA`, and the TEXT offset keywords are zero-padded to 10 digits (`0000000731`).
- **TEXT:** the delimiter is `/` (ASCII 47), and every file has the same 42 keywords.
- **Encoding:** `$DATATYPE` I, `$BYTEORD` 1,2,3,4 (little-endian), `$MODE` L.
- **Event size:** 4 bytes per event, i.e. one byte for each of the four parameters.

## 2. Parameters
They're identical in every file, in this order:

| n | $PnN | $PnS | $PnB | $PnR | $PnE |
|---|---|---|---|---|---|
| 1 | SSC | Side Scatter Signal | 8 | 256 | 0,0 |
| 2 | SFL | Side Fluorescence Signal | 8 | 256 | 0,0 |
| 3 | FSC | Forward Scatter Signal | 8 | 256 | 0,0 |
| 4 | FSCW | Forward Scatter Pulse Width Signal | 8 | 256 | 0,0 |

- There is no time, event-ID, flag or cluster-label parameter, so the time-vs-index plot was skipped.
- There's no `$PnG`, `$PnD` or `$PnV`.
- The order is SSC, SFL, FSC, FSCW, which is not the FSC-first order you might expect.

## 3. Values
- All values are **8-bit linear integers from 0 to 255**. Nearly every value in that range occurs (up to 256 distinct values per parameter), so this is genuine 8-bit data, not a wider signal stored in 8 bits.
- This is a coarse scale, probably the instrument's scattergram resolution rather than its internal signal resolution. That's an inference; the files don't say.

## 4. Complete event lists or gated?
They look like **complete, ungated event lists**, with only an instrument trigger threshold applied:
- **`$TOT` matches the row count in every file:** 45,143 for S1, then 4,602, 4,313 and 4,915. S1 has about 10 times as many events as the others.
- **FSC never goes below 10–11** in any file, and the plots show a flat floor there. That's a trigger threshold on FSC, not a gate.
- **Debris and other non-fluorescent events are kept.** In S4, 8.8% of events have SFL = 0, and every file has a low-SFL smear along SSC. A WBC gate would have removed these.
- **There's heavy saturation at 255.** In S1, 25% of SFL values and 16.5% of FSC values are 255; S2 shows the same at 8% and 3%. The plots show these as solid lines along the top and right edges. These are real off-scale events clipped by the 8-bit range, not a gate. Your generator needs to reproduce these pile-ups.
- **No empty regions with straight-edged boundaries**, which polygon gating would leave.
- **Edge shapes that look like physics:** FSCW has a sharp, curved lower edge that rises with FSC. A pulse can't be narrower than its height allows, so this is physical, not a gate.

## 5. Comparison with Fig 2 and the Rule 1 / Rule 2 table
Compared against the paper's descriptions only, since Fig 2 itself wasn't available here. Without numeric cut-offs this is qualitative.

**SFL vs SSC (standard WDF view):** this looks like a body-fluid WDF plot in every file:
- a compact cluster around SSC 70 / SFL 50 (probably lymphocytes)
- a smaller cluster around SSC 140–160 / SFL 35 (probably neutrophils)
- a diagonal band rising from SSC about 110 to SFL 255. That band is high-fluorescence cells (monocytes/macrophages and atypical or malignant cells) and is very dense in S1.

**Each file against its stated rules:**

| File | Stated | Rule 1 (SFL vs FSCW): what I see | Rule 2 (SFL vs FSC): what I see | Fit |
|---|---|---|---|---|
| S1 | + / + | Many events at FSCW 50–200 with high SFL, plus a saturated SFL row across the whole FSCW range | A dense vertical band at FSC 20–60 running from SFL 60 up to saturation, alongside a large high-FSC population | Fits both |
| S2 | + / − | A sparse spread at FSCW 30–75 with SFL 150–250, and the saturated SFL row reaching FSCW about 200 | A mid-SFL band at FSC about 50, much weaker than S1's | Rule 1 fits. Rule 2 is unclear: there's some mid-SFL, low-FSC signal, which may be what the authors' unpublished cut-off excluded |
| S3 | − / + | Tight column, FSCW mostly 35 or below; only a few saturated events up to FSCW about 110 | A broad cloud at FSC 50–110 with SFL 80–200 | Fits both |
| S4 | − / − | Mostly FSCW 50 or below, with a handful of outliers up to about 170 | Scattered mid-SFL events but no clear population; much of the file is debris at low SFL | Fits both, though S4's outliers look a lot like S2's |

**Bottom line:**
- S1 and S3 match their labels clearly.
- S2's Rule 1 + and S4's double negative are plausible.
- The S2 vs S4 difference on Rule 1 comes down to a handful of events, so it can't be confirmed without the paper's thresholds.

Still to do: open `figures/combined_key_4x3.png` next to Fig 2 to confirm the cluster positions.

## 6. Hints about how the files were exported
- **`$CYT = XN-20`:** that's the name of the XN analyser module, not "XN-1000".
- **`$CYTSN = 11569`:** the instrument serial number.
- **`$SYS = Windows 7`:** probably the Windows PC that runs the analyser's software.
- **`$ORIGINALITY = Original`:** this is an FCS 3.1 keyword appearing in a 3.0 file.
- **`$FIL` (redacted) has the shape `[XX-99^99999][99-99_9][99999999_999999][ XX-99].999`.** It's very likely `[XN-20^11569][…][YYYYMMDD_hhmmss][ sample no].fcs`, an analyser-generated file name, which suggests a direct export from the instrument software rather than a conversion.
- **No software name or version keyword, and no non-`$` (Sysmex-specific) keywords at all.**
- **`$ETIM` is present but `$BTIM` is missing,** so acquisition time can't be calculated.
- **Other redacted values:**
  - `$SMNO` has the shape `XX-99`, probably a sample number like "BF-04".
  - `$CELLS` is 2 letters and `$COM` is 6 letters.
  - `$DATE` is `99-99-9999`.

## 7. What this means for the synthetic data generator
- **Copy the structure exactly:**
  - FCS3.0, `/` delimiter, TEXT at byte 58, zero-padded 10-digit offsets
  - 8-bit little-endian integers in the order SSC, SFL, FSC, FSCW, with `$PnR` 256, `$PnE` 0,0 and the `$PnS` names above
  - the 22 non-parameter keywords listed in `schema.json`
- **Realistic files need:**
  - an FSC floor at 10
  - a spike at SFL = 0 from debris
  - pile-ups at 255 in SFL and FSC (up to about 25% for cell-rich samples)
  - an FSCW lower edge that rises with FSC
  - roughly 4,000–45,000 events per body-fluid file
- **Fabricate** `$FIL`, `$SMNO`, `$DATE`, `$ETIM`, `$CELLS` and `$COM` using the masked shapes.
- **Four malignant pleural effusions can't tell you about:**
  - whole-blood mode (event counts and cluster positions)
  - other channels (WNR, WPC, RET, PLT-F, and the impedance counts)
  - non-malignant or normal body fluids
  - whether other XN software versions export at higher bit depth or with a different set of keywords
  - how much counts and positions vary between instruments

## Suggested changes to the scripts
- **Section 5 of `report.md`** still says "not assessed" because it's generated automatically. The script could leave space for reviewer notes instead.
- **Saturation flags:** the report flags pile-ups of 0.5% or more as possible saturation, so it lists most parameters. A higher threshold for 8-bit data would cut the noise.
