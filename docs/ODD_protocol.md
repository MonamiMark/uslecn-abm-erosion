# ODD Protocol: LS_CN Agent-Based Model

## 1. Overview

### 1.1 Purpose
The model simulates water and sediment movement across heterogeneous agricultural landscapes to evaluate how land-cover configuration (strip-cropping patterns) affects soil erosion estimates. It implements both the classical USLE LS topographic factor and the proposed LS_CN (Curve Number-weighted) variant, enabling direct comparison. The LS_CN method weights flow accumulation by the ratio of runoff from the actual heterogeneous crop pattern to runoff from a uniform reference crop, thereby capturing how upslope land cover modifies downslope erosive power.

### 1.2 Entities, State Variables, and Scales

#### Patches (5×5 m cells)
Each patch represents a land parcel with fixed spatial coordinates. State variables:

| Variable | Description | Units / Values |
|----------|-------------|----------------|
| `patch-elevation` | Elevation from DEM | m |
| `patch-slope-per` | Slope gradient | m/m |
| `patch-slope-deg` | Slope angle | degrees |
| `patch-aspect` | Flow direction azimuth | radians |
| `patch-k` | Soil erodibility | 0.41 (Chernozem) / 0.33 (Cambisol) |
| `patch-c` | Cover-management factor | 0.005–0.8 |
| `patch-cn` | Curve Number (SCS-CN) | 30–76 |
| `patch-r` | Rainfall erosivity | 40 (default) |
| `patch-p` | Support practice factor | 1.0 |
| `flow-acc` | Flow accumulation (upslope contributing area) | dimensionless |
| `cnmod` | List of CN ratios for each unique CN class | list of floats |
| `cn-ratio-base-sum` | Sum of base (reference) CN modifier from upstream | dimensionless |
| `cn-ratio-sum` | Sum of actual CN modifier from upstream | dimensionless |
| `noflow?` | True for local elevation minima (no downslope neighbor) | boolean |
| `drain?` | True for domain boundary / NODATA cells | boolean |
| `inner-land?` | True for cells ≥5 px from domain edge | boolean |
| `patch-g` | Erosion rate (classical USLE LS) | t·ha⁻¹·event⁻¹ |
| `patch-g2` | Erosion rate (LS_CN) | t·ha⁻¹·event⁻¹ |

#### Turtles (water/sediment agents)
Mobile agents that carry flow between patches:

| Variable | Description |
|----------|-------------|
| `frac` | Fraction of upslope area assigned to this agent |
| `cn-modifier` | CN-weighted modifier for the actual crop pattern |
| `cn-modifier-base` | CN-weighted modifier for the reference (uniform) crop |

#### Spatial scale
- **Cell size**: 5 m (matching input DEM resolution)
- **Domain size**: Variable (field blocks 288–600 m width, loaded from ASC files)
- **Extent**: Single agricultural field block

#### Temporal scale
- **Event-based**: Single rainfall event (not continuous simulation)
- **One iteration**: Load DEM → load C/CN factors → compute flow accumulation → calculate erosion

### 1.3 Process Overview and Scheduling

The model executes a single event in deterministic sequence:

1. **Setup** (`setup`): Clear world, load DEM, resize world, compute slope and aspect (Horn's algorithm), identify boundary (drain) and pit (noflow) cells.
2. **Load C and CN factors** (`load-CFCN`): Read C-factor raster and CN raster, assign crop-specific C and CN values to patches based on raster codes (1 = crop1, 2 = crop2).
3. **Prepare flow directions** (`prepare-flows`): Compute multiple-flow-direction (MFD) weights for each patch based on elevation differences to its eight neighbors.
4. **Compute flow accumulation** (`get-flow-accumulation`):
   - **Classical mode** (WF? = false): Iterative turtle-based flow routing; each patch spawns turtle agents carrying flow fractions to downslope neighbors.
   - **LS_CN mode** (WF? = true): For each unique CN class: (a) set all patches to reference-CN modifier, route flow, accumulate `cn-ratio-base-sum`; (b) set all patches to actual-CN modifier, route flow, accumulate `cn-ratio-sum`; (c) compute CN ratio = `cn-ratio-sum / cn-ratio-base-sum` per cell and store in `cnmod`.
5. **Calculate erosion** (`calculate-erosion`): Compute per-cell erosion using LS or LS_CN, report mean erosion across all land cells.

## 2. Design Concepts

### 2.1 Emergence
The difference ΔA between LS and LS_CN erosion estimates emerges from local interactions between flow paths and land-cover boundaries. When high-runoff crops (maize, CN ≈ 75) are upslope of low-runoff crops (wheat, CN ≈ 61), the CN-weighted flow accumulation amplifies downslope erosion beyond what classical LS predicts. Conversely, low-runoff crops upslope of high-runoff crops reduce flow accumulation. The bimodal distribution of ΔA observed in strip-cropping scenarios is not prescribed by any global parameter — it arises from the spatial configuration of CN boundaries relative to flow direction.

### 2.2 Adaptation
Turtles do not adapt — they follow deterministic flow rules based on local topography. The landscape (patches) is static during a single event.

### 2.3 Objectives
Not applicable (turtles have no goals).

### 2.4 Learning
Not applicable.

### 2.5 Prediction
Not applicable.

### 2.6 Sensing
- **Turtles**: Sense elevation of neighboring patches to determine flow direction (via `heading` towards the lower neighbor). They carry fractional flow but do not sense beyond the immediate next cell.
- **Patches**: During `prepare-flows`, each patch senses elevation of all eight neighbors to compute MFD weights.

### 2.7 Interaction
Turtles interact indirectly through flow accumulation on patches. When multiple turtles arrive at the same patch, their `frac` values are summed to update `flow-acc`, and their `cn-modifier`/`cn-modifier-base` values are summed to update `cn-ratio-sum`/`cn-ratio-base-sum`. The patch then spawns new turtles carrying the accumulated flow fraction forward.

### 2.8 Stochasticity
- **Initial turtle positions**: Not explicitly random — flow begins from every land cell (each patch initially has `flow-acc = 1`, and all land cells spawn turtles in parallel). There is no Monte Carlo element.
- **Rainfall depth** (`srazky-mm`): A model parameter (10–120 mm), applied deterministically through the SCS-CN runoff equation (`CN-R`).

### 2.9 Collectives
Not applicable.

### 2.10 Observation
Primary output: `total-erosion` — mean erosion rate across all non-boundary land cells (t·ha⁻¹·event⁻¹). Secondary output: `highest-c-factor-representation` — proportion of the lower slope occupied by the highest C-factor crop, used to diagnose erosion spatial patterns. It is recorded as a metric in several BehaviorSpace experiments (e.g. `cernozemePK`, `ePKnt`, `kambizemeKP`) as an internal diagnostic for checking scenario-generation consistency, but is not reported as a result in the manuscript's main text. Per-cell erosion maps (`patch-g`, `patch-g2`) are visualized via color scale. Flow accumulation surfaces can be exported to ASC format via `export-to-asc`.

## 3. Details

### 3.1 Initialization
1. **Load DEM**: Read ASCII Grid file (`.asc`), extract header (NCOLS, NROWS, XLLCORNER, YLLCORNER, CELLSIZE), create NetLogo world with matching dimensions.
2. **Set soil type**: Choose Chernozem (K = 0.41) or Cambisol (K = 0.33).
3. **Set slope morphology**: Choose from plane, convex, concave (synthetic) or ce1–ce5, ka1–ka5 (real-field DEMs).
4. **Set flow direction**: parallel, divergent, or convergent (determines which DEM variant is loaded).
5. **Set division pattern**: single (uniform), two (two parts), stripes (alternating), stripe-inside, or one110 (110 m top strip).
6. **Set division angle**: 0–90° in 10° or 15° steps.
7. **Set stripe length**: 25–250 m for the `stripes` division mode used in the strip-cropping scenario matrix (width of individual stripes; matches the manuscript's Section 2.5.1). The interface chooser also offers 10 m and 20 m, but these are exercised only by the separate `stripe-inside` division mode (e.g. BehaviorSpace experiment `p400PU`), not by the `stripes` scenarios reported in the paper.
8. **Set crop rotation**: Choose crop1 (downslope) and crop2 (upslope) from 20 crop types with specific C and CN values.
9. **Set rainfall**: `srazky-mm` = 10–120 mm.
10. **Toggle WF?**: Enable/disable CN-weighted LS_CN computation.

### 3.2 Input Data

#### DEM files (`.asc`)
Generated by Python scripts (`CreateASC.ipynb`). Synthetic terrain types:
- **plane_parallel.asc, plane_divergent.asc, plane_convergent.asc**
- **convex_parallel.asc, convex_divergent.asc, convex_convergent.asc**
- **concave_parallel.asc, concave_divergent.asc, concave_convergent.asc**
- **ce1–ce5, ka1–ka5**: Real-field DEMs from Chernozem and Cambisol regions

#### C-factor rasters (`.asc`)
Symbolic values: 1 = first crop (crop1), 2 = second crop (crop2). Actual C factors are assigned in NetLogo from the crop parameter table (e.g., maize = 0.61, wheat = 0.12, grass = 0.005). Files include:
- `C_factor_uniform.asc` (single crop)
- `C_two_<angle>.asc` (two blocks)
- `C_striped_<angle>_<width>m.asc` (alternating stripes)
- `single_stripe_<angle>_<width>m.asc`

#### CN maps
Same raster structure as C-factor files; values 1 or 2 map to crop-specific CN values (maize CN = 66–76, wheat CN = 61–72, grass CN = 30–58) depending on soil type.

### 3.3 Submodels

#### Flow routing (MFD)
Multiple-flow-direction algorithm adapted from Quinn et al. (1991). For each patch, elevation differences to all eight neighbors are computed. Each difference is weighted by distance factor (0.354 for diagonals, 0.5 for cardinal directions). The proportion of flow sent to neighbor *i* is:

$$P_i = \frac{\max(0, \Delta E_i \cdot w_i)}{\sum_{j=1}^{8} \max(0, \Delta E_j \cdot w_j)}$$

where $\Delta E_i$ is the elevation drop to neighbor *i* and $w_i$ is the distance weight. A turning-point threshold (0.3–0.5 × slope) prevents flow to upslope neighbors with very small elevation differences (numerical noise).

#### LS computation (classical USLE)
After flow accumulation (`flow-acc`) is computed, the LS factor follows Desmet & Govers (1996):

$$L = \left(\frac{A}{22.13 \cdot d \cdot (|\sin\alpha| + |\cos\alpha|)}\right)^m, \quad m = \frac{\beta}{\beta+1}$$

$$\beta = \frac{\sin\theta}{0.0896 \cdot (3 \cdot \sin^{0.8}\theta + 0.56)}$$

$$S = -1.5 + \frac{17}{1 + e^{2.3 - 6.1\sin\theta}}$$

where $A$ = upslope area (flow-acc × cell area), $d$ = cell size, $\theta$ = slope angle, and $\alpha$ = cell aspect (Horn 1981 algorithm, Section 3.3 below); the term $|\sin\alpha| + |\cos\alpha|$ is the Desmet & Govers (1996) aspect correction of the unit contributing area (matches `usle-base-g` in Supplement B, and Supplement A Section A.2.1). Erosion: $E = R \cdot K \cdot LS \cdot C \cdot P$.

#### LS_CN computation (CN-weighted)
The flow accumulation is weighted by runoff ratio:

$$A_{CN} = A \cdot \frac{Q_{actual}}{Q_{reference}}$$

where $Q$ is runoff depth from the SCS-CN equation:

$$S = \frac{25400 - 254 \cdot CN}{CN}$$

$$Q = \frac{(P - 0.2S)^2}{P + 0.8S} \quad \text{if } P > 0.2S, \text{else } 0$$

The CN weighting is computed iteratively: for each unique CN class, flow is routed once with all cells at the reference CN (uniform crop) and once with actual CN values. The ratio of accumulated CN modifiers ($cnRatioSum / cnRatioBaseSum$) at each cell becomes the weight applied to flow accumulation, implemented as `cnmod` (list of ratios per CN class). The final LS_CN computation:

$$L_{CN} = \left(\frac{A \cdot \text{cnmod}_{cn}}{22.13 \cdot d \cdot (|\sin\alpha| + |\cos\alpha|)}\right)^m$$

where $\text{cnmod}_{cn}$ is the CN ratio corresponding to the patch's CN class, and $\alpha$ is the cell aspect as in the classical $L$ equation above (matches `usle-base-g2` in Supplement B). The slope factor $S$ is identical to the classical formulation.

#### Slope and aspect (Horn's algorithm)
Using the 8-neighbor moving window (Horn, 1981):

$$[dz/dx] = \frac{(c + 2f + i) - (a + 2d + g)}{8 \cdot \text{cellsize}}$$

$$[dz/dy] = \frac{(g + 2h + i) - (a + 2b + c)}{8 \cdot \text{cellsize}}$$

$$\text{slope} = \sqrt{[dz/dx]^2 + [dz/dy]^2}, \quad \text{aspect} = \arctan(-dz/dx, dz/dy)$$

#### Crop parameter table
20 crop types with predefined C factor and CN values (two sets: Chernozem and Cambisol):

| Crop | C factor | CN (Chernozem) | CN (Cambisol) |
|------|----------|----------------|----------------|
| Winter wheat | 0.12 | 60.5 | 71.75 |
| Winter rye | 0.17 | 60.5 | 71.75 |
| Spring barley | 0.15 | 60.5 | 71.75 |
| Winter barley | 0.17 | 60.5 | 71.75 |
| Oats | 0.10 | 60.5 | 71.75 |
| Maize (grain) | 0.61 | 66.33 | 75.67 |
| Legumes | 0.05 | 59.5 | 72.17 |
| Early potatoes | 0.60 | 66.33 | 75.67 |
| Late potatoes | 0.44 | 66.33 | 75.67 |
| Grassland | 0.005 | 30 | 58 |
| Hops | 0.80 | 44 | 65.33 |
| Winter rapeseed | 0.22 | 66.33 | 75.67 |
| Sunflower | 0.60 | 66.33 | 75.67 |
| Poppy | 0.50 | 66.33 | 75.67 |
| Other oil crops | 0.22 | 66.33 | 75.67 |
| Maize (silage) | 0.72 | 66.33 | 75.67 |
| Annual fodder | 0.02 | 59.5 | 72.17 |
| Perennial fodder | 0.01 | 59.5 | 72.17 |
| Vegetables | 0.45 | 66.33 | 75.67 |
| Orchards | 0.45 | 44 | 65.33 |

## Metadata
- **Software**: NetLogo 7.0.2 (every run archived in this repository was produced with 7.0.2; earlier revisions of this model ran under NetLogo 6.4)
- **Extensions**: GIS, Palette
- **Repository**: Zenodo DOI 10.5281/zenodo.17531041
- **Author**: Marek Bednář
- **Language**: Czech (UI labels, interface); English variable names
- **License**: Not specified
