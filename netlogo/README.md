# NetLogo model

Two files are archived here:

| File | Status |
|---|---|
| `usle_abm_model_LE_LFIX.nlogo` | **Model version used for the archived runs.** Use this one. |
| `usle_abm_model.nlogo` | Earlier revision (v1.0.0 era), kept for reference only. Its L-factor expression is superseded — see `../CHANGELOG.md`. |

Note that the filename suffix `LE_LFIX` is a working label from the model's development
history, not a reference to a journal.

## Requirements

NetLogo **7.0.2** (or a compatible 7.x). The BehaviorSpace tables in `data/outputs/raw/`
record `NetLogo 7.0.2` and `Table version 2.0` in their headers.

## Running

1. Open the model in NetLogo.
2. **The model switches its working directory to its own folder on load.** Every `.asc`
   input must therefore sit next to the `.nlogo` file. Copy the rasters you need from
   `../data/virtual_blocks/`, `../data/realblocks/` and `../data/landuse/` into this
   folder, or copy the model next to them.
3. Set the choosers: terrain morphology, flow direction, soil region, division type,
   strip length, strip orientation, rainfall depth.
4. `WF?` selects the formulation — `false` runs classical LS, `true` runs LS_CN. A paired
   run is the same scenario executed once with each setting; the two rows are paired on
   every factor column.
5. `Setup`, then `Go`.

## Raster naming

Inputs are not listed in a manifest; the model derives the filenames from the choosers.

| Input | Filename convention |
|---|---|
| Terrain (synthetic) | `<morphology>_<flow_direction>.asc`, e.g. `convex_convergent.asc` |
| Terrain (real DEM) | `<morphology>f.asc` |
| C factor (strip-cropping) | `C_striped_<angle>_<length>m.asc` |
| C factor (two-division) | `C_two_<angle>.asc` |
| C factor (uniform) | `C_factor_uniform.asc` |

Not every combination of angle and width exists on disk; the available set is what is
committed under `../data/landuse/`.

## BehaviorSpace

The experiment definitions are embedded in the model file, so a headless run needs no
external specification. `../analysis/powershell/run_all.ps1`, `make_chunks.ps1` and
`rerun_available.ps1` are the drivers used to produce the archive, including the chunking
scheme that splits a large experiment across processes (`<parent>_sl<number>.csv`; a chunk
is one part of a single experiment, not a separate design).

`debug?` clips the local runoff modifier to 0.5–2.0. It was off for every archived run; a
run with it on is not comparable with the rest of the data.

## Output

BehaviorSpace writes one CSV per experiment with a seven-line header and **CP1250**
encoding. `../analysis/R/01_analyse_LFIX.R` parses exactly that format and pairs the
`WF? = false` and `WF? = true` rows of each scenario.
