# uslecn-abm-erosion

NetLogo implementation of **LS_CN**, a runoff-weighted contributing-area index for
erosion modelling in heterogeneous agricultural landscapes, with the complete paired
simulation outputs and the R analysis code behind the manuscript by Bednář and Šarapatka.

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.17531041.svg)](https://doi.org/10.5281/zenodo.17531041)

**Current version: 1.2.0** — see [CHANGELOG.md](CHANGELOG.md). Version 1.2.0 adds the
complete simulation outputs and the analysis code, and corrects the L-factor expression
used in earlier versions.

---

## What LS_CN is

Classical LS assumes that runoff is generated uniformly across the contributing area of a
cell. In a strip-cropped field this is rarely true: an upslope strip of a high-runoff crop
feeds more water downslope than a strip of a protective crop does. LS_CN keeps the RUSLE
slope-length/slope-steepness form and replaces the contributing area with a
runoff-weighted one:

```
LS_CN = LS × (Q_struct / Q_homo)^m
```

where `Q_struct` is the SCS-CN event runoff produced by the actual crop mosaic and
`Q_homo` is the runoff produced by a homogeneous counterfactual carrying the receiving
cell's own CN under the same rainfall. The ratio multiplies the **contributing area**, not
the slope length, and therefore sits inside the exponent: the erosion ratio of a pair is
`A_CN / A_LS = (Q_struct/Q_homo)^m` with `m` the local RUSLE slope-length exponent.

`R`, `K`, `C` and `P` are left unchanged. LS_CN is not a replacement for MUSLE: it does
not use event runoff volume or peak discharge in place of the erosivity term.

## What this study claims, and what it does not

The evidence is a **model-to-model comparison under a defined structural counterfactual**.
Across 7,650 pairable scenarios (10 mm events excluded, see below) LS_CN yields lower
soil-loss values than classical LS, with a mean paired difference of −23.8 % and a median
of −18.3 %.

This does **not** show that classical LS overestimates measured erosion, and nothing here
is validated against field observations. The repository contains no measured runoff, soil
loss or sediment yield; the model performs no sediment routing or deposition; the real-DEM
scenarios use DMR 4G derivatives as terrain templates and are not field plots. The
statistical models are descriptive — paired rows are not independent observations.

## Repository contents

```
├── .zenodo.json                      record metadata for Zenodo
├── CHANGELOG.md                      version history
├── netlogo/
│   ├── usle_abm_model_LE_LFIX.nlogo  model version used for the archived runs
│   ├── usle_abm_model.nlogo          earlier revision, kept for reference
│   └── README.md
├── analysis/
│   ├── R/                            pairing script and the Table 1 / Table 2 scripts
│   └── powershell/                   batch drivers for headless BehaviorSpace runs
├── data/
│   ├── landuse/                      C-factor strip patterns (33 orientations × widths)
│   ├── realblocks/                   terrain templates derived from DMR 4G
│   ├── virtual_blocks/               synthetic terrain blocks (3 shapes × 3 flow patterns)
│   └── outputs/
│       ├── raw/                      33 BehaviorSpace tables, as exported (CP1250)
│       └── derived/pairs.csv         8,730 paired scenarios
├── docs/
│   ├── ODD_protocol.md               model description in ODD format
│   ├── parameters.md                 parameter values
│   ├── SUPPLEMENT_A_Technical_Methods.md
│   ├── SUPPLEMENT_B_ABM_Implementation.md
│   └── console_logs/                 console output of analysis steps 01 and 02
├── python/                           DEM and land-use generators
└── LICENSE                           MIT
```

## Requirements

| Component | Version |
|---|---|
| NetLogo | 7.0.2 (the archived `.nlogo` files are 7.x) |
| R | 4.4, packages `dplyr` and `mgcv` |
| Python | 3.8+, `numpy`, `matplotlib` (see `python/requirements.txt`) |

## Quick start — reproduce the numbers without re-running the model

The archived outputs are sufficient to regenerate every statistic in the manuscript.

```bash
cd analysis/R

# rebuild the paired table from the raw BehaviorSpace exports
Rscript 01_analyse_LFIX.R

# manuscript Table 1 (descriptive LM) and Table 2 (descriptive GAM)
Rscript 05_table1_lm_paired_difference.R
Rscript 06_table2_gam_absolute_soil_loss.R
```

Paths default to the repository layout when a script is run from `analysis/R`, and can be
overridden with `LSCN_RAW`, `LSCN_DERIV`, `LSCN_PAIRS` and `LSCN_TWO_VIEWS_OUT`.

Verified: `01_analyse_LFIX.R` regenerates `data/outputs/derived/pairs.csv` byte-identically
(SHA-256 `7578367b578d49e4296fe7b172a7b949a65aff1a1b535e45e0e73285df932042`), and the two
table scripts reproduce the published coefficients exactly:

| Table | Result |
|---|---|
| 1 | n = 7,200; R² = 0.2622; AIC = 42,351.0 |
| 2 | n = 14,400 rows; deviance explained 57.80 %; AIC = 78,631.8; method[LS_CN] = −4.674 |

## Quick start — re-run the model

1. Open `netlogo/usle_abm_model_LE_LFIX.nlogo` in NetLogo 7.0.2.
2. The model switches its working directory to its own folder on load, so the `.asc`
   rasters must sit next to the `.nlogo` file.
3. Choose a DEM (synthetic block or DMR-derived), a C-factor raster from `data/landuse/`,
   a soil region and a rainfall depth; `WF?` toggles between classical LS (`false`) and
   LS_CN (`true`).
4. BehaviorSpace experiment definitions are embedded in the model file; the batch drivers
   in `analysis/powershell/` reproduce the headless workflow used for the archive.

A single scenario takes roughly 2 s to over 2 min depending on the number of distinct CN
classes (each class requires its own flow-accumulation pass) and on strip length; ticking
`debug?` clips the local runoff modifier to 0.5–2 and produces a different model
behaviour, so leave it off.

## Data notes

- `data/outputs/raw/*.csv` are BehaviorSpace exports in **CP1250** with a seven-line
  header. Do not re-encode them; `01_analyse_LFIX.R` reads them accordingly.
- Ten-millimetre events produce no runoff under `Ia = 0.2 S` for every CN in the table, so
  `A_CN` is exactly zero and the paired difference is −100 % by construction. They are
  retained in `pairs.csv` and flagged `rain_ok = FALSE`; all summary statistics use the
  7,650 rows with `rain_ok = TRUE`.
- A cell-wise factor signature does not uniquely identify a scenario, because the terrain
  template differs between experiment families (for example the 400 m and 500 m block
  variants) and that difference is encoded only in `experiment`/`parent`. Key on
  (`experiment`, `key`).
- `A_LS` and `A_CN` are the model's `total-erosion` values in t·ha⁻¹·yr⁻¹. Both members of
  a pair share identical `R`, `K`, `C` and `P`, so differences and ratios between them do
  not depend on the absolute calibration of those factors.

## Data sources

Real terrain: DMR 4G (5 × 5 m) from the Czech Office for Surveying, Mapping and Cadastre
(ČÚZK), https://geoportal.cuzk.cz/. Raw DMR 4G tiles are not redistributed for licensing
reasons; `data/realblocks/` contains derived ASC rasters prepared from them for model
demonstration and testing.

Synthetic terrain and land-use patterns are generated by the scripts in `python/`.

## Parameters

- Grid: 120 × 120 cells, 5 × 5 m (600 × 600 m)
- Surfaces: plane, convex, concave; flow patterns: parallel, divergent, convergent
- Strip widths: 25–250 m; orientations 0–90° relative to the contour
- Crops: maize vs. winter wheat (and other cereals/root crops in the CN table)
- Soil regions: Chernozem (South Moravia), Cambisol (Bohemian–Moravian Highlands)
- Rainfall depths: 10, 30, 50, 60, 120 mm

See `docs/parameters.md` for the full specification.

## Citation

If you use this code or these data, please cite the archived record:

```bibtex
@software{bednar_2026_uslecn_abm_erosion,
  author    = {Bedn{\'a}{\v r}, Marek and {\v S}arapatka, Bo{\v r}ivoj},
  title     = {uslecn-abm-erosion: NetLogo implementation of a runoff-weighted LS factor
               (LS\_CN), paired simulation outputs and R analysis code},
  year      = {2026},
  version   = {1.2.0},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.17531041},
  url       = {https://doi.org/10.5281/zenodo.17531041}
}
```

## License

Code: MIT (see `LICENSE`). Data and documentation: CC BY 4.0.

## Contact

Marek Bednář — Department of Ecology and Environmental Sciences, Palacký University in
Olomouc, Czech Republic — marek.bednar@upol.cz — ORCID 0000-0002-8832-0919

## Acknowledgements

Supported by the Technology Agency of the Czech Republic: project SS02030018 (Centre for
Landscape and Biodiversity) and project SS06010290 (Strip cropping management as an
adaptation measure to optimize landscape water management).
