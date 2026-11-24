# Changelog

## 1.2.2 — 2026-11-23

Completes the byte fidelity fix; corrects an ineffective step in 1.2.1.

v1.2.1 added `.gitattributes` with `* -text` but did not re-hash the data files. Git had
already staged them, and because their recorded stat data had not changed it never applied
the new attribute: the archive published from v1.2.1 still stored
`data/outputs/derived/pairs.csv` as 3,084,617 bytes (LF), while the working tree held
3,093,348 bytes (CRLF). `git add --renormalize .` was required to force the conversion to
be undone.

This release re-normalises the data files, so the checksum quoted in `README.md` now
matches the archive. No code, data values or metadata changed.

Note on the version history: the records for 1.2.0 and 1.2.1 are published and cannot be
altered. The 1.2.1 record was also published under the version label "1.2.0" because
`.zenodo.json` had not been bumped; its metadata label has since been corrected to 1.2.1,
but its archived files still carry LF line endings. Use 1.2.2.

## 1.2.1 — 2026-11-23

Added `.gitattributes` with `* -text`, so that git stores files verbatim on every platform
instead of rewriting CRLF to LF on commit. On its own this version did not change the
already-staged bytes — see 1.2.2.

## 1.2.0 — 2026-11-23

This version makes the archive reproducible: it adds the complete simulation outputs and
the analysis code, and corrects the model expression that produced the earlier results.

### Corrections

1. **L-factor exponentiation.** Earlier versions computed

   ```netlogo
   let lf ( fa / (22.13 * dmr-res * (abs (sin(p-asp)) + abs (cos(p-asp)))) ^ (beta / (beta + 1)) )
   ```

   In NetLogo `^` binds more tightly than `/`, so the exponent was applied to the
   denominator only and `L` grew **linearly** with flow accumulation instead of as
   `flow-acc^m`. The numerator also lacked the cell-size term needed to convert cell
   counts to a specific contributing area. The combined bias was
   `fa^(1−m) · 25^(−m)`: it vanished at exactly 25 contributing cells and grew in both
   directions away from that point, so it distorted the spatial pattern as well as the
   absolute values. The corrected form, used for every run archived in this version, is

   ```netlogo
   let lf (((fa * dmr-res) / (22.13 * (abs (sin(p-asp)) + abs (cos(p-asp))))) ^ (beta / (beta + 1)))
   let lf (((flow-acc * modi * dmr-res) / (22.13 * (...))) ^ (beta / (beta + 1)))   ; LS_CN
   ```

   Because the runoff ratio multiplies the contributing area and not the slope length, it
   belongs inside the exponent, and the erosion ratio of a pair is `modi^m` rather than
   `modi`. This is what the technical supplement had always specified; the code now
   matches it.

2. **SCS-CN denominator.** The direct-runoff expression now uses `P + 0.8 S`, consistent
   with the initial abstraction `Ia = 0.2 S` that the same code applies. Earlier versions
   mixed `Ia = 0.2 S` with a `P + 0.85 S` denominator.

3. **Truncated rasters.** `data/realblocks/ce1.asc` and
   `data/virtual_blocks/plane_parallel.asc` were stored as 1-byte files in earlier
   versions, and `data/realblocks/ce4.asc` was missing. All three are now the complete
   rasters (69,550 B, 36,450 B and 68,806 B).

4. **README claims.** Text asserting a 15–30 % reduction, more than 20,000 scenarios, a
   40–70 mm sensitivity window, hotspot identification and generalisation to measured
   erosion has been removed. It did not follow from the archived outputs, and the
   analysis supports a narrower statement: a model-to-model difference under a defined
   homogeneous counterfactual. The current statement of scope is in `README.md`.

### Additions

- `data/outputs/raw/` — 33 BehaviorSpace tables (14 experiment families).
- `data/outputs/derived/pairs.csv` — 8,730 paired scenarios, and `coverage.csv`.
- `analysis/R/` — the pairing script and the two scripts that reproduce Tables 1 and 2.
- `analysis/powershell/` — the batch drivers used for the headless runs.
- `netlogo/usle_abm_model_LE_LFIX.nlogo` — the corrected model.
- `docs/ODD_protocol.md` — expanded ODD description, replacing the shorter version
  shipped with v1.0.0; the stated NetLogo version is corrected to 7.0.2.
- `docs/SUPPLEMENT_A_Technical_Methods.md`,
  `docs/SUPPLEMENT_B_ABM_Implementation.md`, `docs/console_logs/`.

### Note on the R scripts

Only the input/output path block differs from the versions used for the manuscript. The
scripts default to the repository layout and can be redirected with `LSCN_RAW`,
`LSCN_DERIV`, `LSCN_PAIRS` and `LSCN_TWO_VIEWS_OUT`.

## 1.1.0 — 2026-02-28

Metadata and release-naming revision; the archived file set was unchanged from 1.0.0.

## 1.0.0 — 2025-11-05

First archived snapshot: synthetic-DEM and land-use generators, the NetLogo model
revision of the time, the ODD protocol and parameter documentation.
