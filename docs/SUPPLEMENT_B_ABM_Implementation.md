# Supplement B: Agent-Based Model Implementation

This supplement provides technical details of the NetLogo ABM implementation.
Main text references point here for model architecture, agent definitions, and
procedure pseudocode.

## Contents

1. Model Architecture
2. Agent and Patch Definitions
3. Key Procedures and Pseudocode
4. Parameter Initialization
5. Output Generation

---

## B.1 Model Architecture

The erosion ABM uses a raster-based landscape representation built on the NetLogo GIS extension. The model operates on a regular grid of patches, where each patch represents a landscape cell loaded from ASCII Grid (`.asc`) raster files.

- **Extensions:** `gis` (raster file I/O and spatial queries), `palette` (visualization)
- **Patches (landscape cells):** Each patch stores elevation, slope, aspect, USLE factors (K, C, R), Curve Number (CN), accumulated flow, and computed erosion. Resolution matches the input DEM (typically 5 m/pixel).
- **Turtles (flow agents):** Fractional water/sediment particles that route flow from upslope to downslope patches. Each turtle carries a flow fraction (`frac`) and a CN-modifier that adjusts infiltration along its path.
- **Simulation sequence:**
  1. Load DEM and initialize patch properties (`setup`, `setup-land`)
  2. Load C-factor and CN rasters, map symbolic values to crop parameters (`load-CFCN`)
  3. Compute slope and aspect using the Horn algorithm (`update-slope-and-aspect`)
  4. Compute flow routing weights for each patch (`prepare-flows`)
  5. Create turtles and route them downslope to accumulate flow (`prepare-turtles-Dall`, `turtles-move-forward`)
  6. Compute erosion using classical LS and CN-weighted LS_CN variants (`calculate-erosion`)

Two flow-accumulation modes are supported: a standard mode (`WF? = false`) and a CN-weighted mode (`WF? = true`) where each flow fraction is scaled by the ratio of runoff coefficients derived from local and reference CN values.

## B.2 Agent and Patch Definitions

### Patches

```netlogo
patches-own [
  patch-elevation       ; m, elevation from DEM
  patch-slope-per       ; slope as proportion (rise/run)
  patch-slope-deg       ; slope in degrees
  patch-aspect          ; slope aspect (degrees from north)
  patch-k               ; USLE K factor (soil erodibility)
  patch-c               ; USLE C factor (cover management)
  patch-cn              ; Curve Number (infiltration capacity)
  patch-r               ; rainfall erosivity (MJ mm ha-1 h-1)
  patch-p               ; precipitation flag (always 1)
  flow-acc              ; accumulated flow (dimensionless, starts at 1)
  cnmod                 ; list of CN-modifiers per base CN class
  cn-ratio-base-sum     ; cumulative base CN ratio
  cn-ratio-sum          ; cumulative actual CN ratio
  noflow?               ; true if no downslope neighbor exists
  flows                  ; list of flow fractions to 8 neighbors
  drain?                ; true if patch is a boundary/sink
  balance               ; mass balance check variable
  patch-g               ; classical USLE erosion (t ha-1)
  patch-g2              ; CN-weighted LS_CN erosion (t ha-1)
  inner-land?           ; true if patch is >5 cells from boundary
]
```

Patches are classified into three groups: `land` (active computation area), `sink` (boundary/drainage cells), and `inner-land` (interior cells used for statistics, excluding edge effects).

### Turtles (Flow Agents)

```netlogo
turtles-own [
  frac                  ; fraction of flow carried (0-1)
  cn-modifier           ; CN-adjusted flow weight (WF mode)
  cn-modifier-base      ; base CN flow weight (WF mode)
]
```

Turtles are ephemeral: they are created at upslope patches, move one step downslope, transfer their flow fraction to the target patch's `flow-acc`, and are then destroyed. New turtles are spawned at each receiving patch to continue routing.

## B.3 Key Procedures

### setup — Model Initialization

Loads the DEM file, resizes the NetLogo world to match raster dimensions, and initializes all patches. The DEM filename is constructed from the morphology type and flow direction:

```netlogo
to setup
  clear-all
  reset-ticks
  setup-interface
  ; Construct filename: e.g. "plane_parallel.asc" or "konzexef.asc"
  set dmt-file (word morphology "_" flow_direction ".asc")
  set elevation gis:load-dataset dmt-file
  ; Parse header: NCOLS, NROWS, XLLCORNER, YLLCORNER, CELLSIZE
  resize-world 0 ncols - 1 0 nrows - 1
  gis:set-world-envelope gis:envelope-of elevation
  set dmr-res cellsize
  setup-land       ; classify patches, compute slope/aspect
end
```

`setup-land` assigns elevation values from the raster, marks boundary patches as `drain?`, identifies `noflow?` patches (local minima with no downslope neighbor), and calls `update-slope-and-aspect`.

### update-slope-and-aspect — Terrain Analysis

Computes slope and aspect using the Horn (1981) 3×3 finite-difference method:

```netlogo
to update-slope-and-aspect
  ask land [
    let a [patch-elevation] of patch-at -1 1   ; top-left
    let b [patch-elevation] of patch-at 0 1    ; top-center
    let c [patch-elevation] of patch-at 1 1    ; top-right
    let d [patch-elevation] of patch-at -1 0   ; mid-left
    let ee patch-elevation                      ; center
    let f [patch-elevation] of patch-at 1 0    ; mid-right
    let g [patch-elevation] of patch-at -1 -1  ; bot-left
    let h [patch-elevation] of patch-at 0 -1   ; bot-center
    let i [patch-elevation] of patch-at 1 -1   ; bot-right
    let dz-dy ((g + 2*h + i) - (a + 2*b + c)) / (8 * dmr-res)
    let dz-dx ((c + 2*f + i) - (a + 2*d + g)) / (8 * dmr-res)
    let dzxy (dz-dy ^ 2 + dz-dx ^ 2) ^ 0.5
    set patch-slope-deg atan dzxy 1
    set patch-slope-per dzxy
    set patch-aspect atan (- dz-dx) dz-dy
  ]
end
```

### load-CFCN — Land Cover Assignment

Loads C-factor and CN rasters. Symbolic values (1 = crop 1, 2 = crop 2) are replaced with actual parameter values from the crop database based on the selected crop pair and soil type.

### prepare-flows — MFD Flow Routing

For each active patch, computes flow fractions to all 8 neighbors using the Multiple Flow Direction (MFD) algorithm. Flow is distributed proportionally to slope-weighted elevation differences, with diagonal neighbors weighted by √2/2:

```netlogo
to prepare-flows
  ask land [
    let neighbors-offsets [[-1 1] [0 1] [1 1] [-1 0] [1 0] [-1 -1] [0 -1] [1 -1]]
    let weights [0.354 0.5 0.354 0.5 0.5 0.354 0.5 0.354]
    let elevation-diffs []
    foreach neighbors-offsets [ offset ->
      let neighbor patch-at (item 0 offset) (item 1 offset)
      set elevation-diffs lput (ee - [patch-elevation] of neighbor) elevation-diffs
    ]
    ; Slope-weighted distribution
    let slopes (map [ [diff weight] ->
      ifelse-value (diff > 0) [diff * weight * dmr-res] [0]
    ] elevation-diffs weights)
    let total-sum reduce + slopes
    set flows (map [val -> ifelse-value (total-sum > 0) [val / total-sum] [0]] slopes)
  ]
end
```

A turning-point threshold suppresses weak flow directions: slopes below 30% (or 50% for gentle slopes) of the patch slope are zeroed out, concentrating flow into dominant directions.

### prepare-turtles-Dall / prepare-turtles-Dall-base — Turtle Creation

Creates flow-routing turtles at each patch. For each computed flow direction exceeding a minimum fraction threshold (`par-minfrac`), a turtle is spawned heading toward the downslope neighbor:

```netlogo
to prepare-turtles-Dall [sum-flow cnm-base cnm]
  (foreach flows [-1 0 1 -1 1 -1 0 1] [1 1 1 0 0 -1 -1 -1] [
    [flow row col] -> if flow > par-minfrac [
      let target-patch patch-at row col
      if not (target-patch = nobody) and
         [patch-elevation] of target-patch < patch-elevation [
        sprout 1 [
          set heading towards target-patch
          set frac sum-flow * flow
          set cn-modifier cnm * flow
          set cn-modifier-base cnm-base * flow
        ]
      ]
    ]
  ])
end
```

### turtles-move-forward — Recursive Flow Routing

All turtles advance one step downslope. At the receiving patch, the sum of incoming turtle fractions is added to `flow-acc`. New turtles are then spawned to continue routing. The procedure recurses until no turtles remain:

```netlogo
to turtles-move-forward
  ask turtles [ forward 1 ]
  ask patches with [noflow? or drain?] [ ask turtles-here [die] ]
  ask land with [any? turtles-here] [
    let sum-flow sum [frac] of turtles-here
    set flow-acc flow-acc + sum-flow
    ask turtles-here [die]
    prepare-turtles-Dall sum-flow ...  ; re-spawn for next step
  ]
  if any? turtles [ turtles-move-forward ]
end
```

### calculate-erosion — USLE Computation

Erosion is computed per patch using the USLE formula. The LS factor is derived from flow accumulation and slope using the MUSLE-based formulation:

```netlogo
to-report usle-base-g [p]
  let beta sin(slope-deg) / (0.0896 * (3 * sin(slope-deg) ^ 0.8 + 0.56))
  let lf (flow-acc / (22.13 * cellsize * (abs(sin(asp)) + abs(cos(asp)))) ^ (beta / (beta + 1)))
  let sf -1.5 + 17 / (1 + exp(2.3 - 6.1 * sin(slope-deg)))
  report C * R * P * K * lf * sf
end
```

In CN-weighted mode (`WF? = true`), the flow accumulation term is multiplied by a CN-modifier (`modi`) derived from the ratio of runoff coefficients S/825 for local vs. reference CN, producing the LS_CN variant stored in `patch-g2`.

## B.4 Parameter Initialization

### Configuration Matrix

Each simulation scenario is defined by the intersection of the following parameter sets:

| Parameter | Values | Count |
|-----------|--------|-------|
| `block-size` | 288, 400, 500, 600 m | 4 |
| `stripe-width` | 25–250 m (10 widths per block) | 10 |
| `stripe-angle` | 0°–90° in 15° steps | 7 |
| `morphology` | plane, convex, concave | 3 |
| `flow_direction` | parallel, divergent, convergent | 3 |
| `soil` | černozem (K=0.41), kambizem (K=0.33) | 2 |
| `crop1 / crop2` | 20 crop types from database | varies |

Total unique scenarios: 4 × 10 × 7 × 3 × 3 × 2 = 5,040 (before crop pairing).

### Crop Parameter Database

Each crop is defined by [name, C-factor, CN_chernozem, CN_cambisol]:

```netlogo
set plodiny-parametry [
  ["pšenice ozimá"      0.12 60.5  71.75]
  ["kukuřice na zrno"   0.61 66.33 75.67]
  ["louky"              0.005 30   58   ]
  ["brambory rané"      0.6  66.33 75.67]
  ; ... (20 crops total)
]
```

CN values are soil-specific: chernozem (lower CN, higher infiltration) and cambisol (higher CN, lower infiltration). The CN modifier in WF mode is computed as the ratio of runoff coefficients: `R_local / R_reference`, where `R = (P - 0.2·S)² / (P + 0.8·S)` and `S = 25400/CN - 254`.

## B.5 Output Generation

### Spatial Erosion Rasters

After simulation, erosion values are exported as ASCII Grid files:

```netlogo
to export-to-asc
  file-open filename
  file-print (word "ncols " world-width)
  file-print (word "nrows " world-height)
  file-print (word "xllcorner " x-min)
  file-print (word "yllcorner " y-min)
  file-print (word "cellsize " cell-size)
  file-print (word "NODATA_value " no-data-value)
  ; Write patch values row by row
  ask patches [
    ifelse drain? [ file-type no-data-value ] [ file-type flow-acc ]
  ]
  file-close
end
```

### Aggregate Statistics

- **Mean erosion** per simulation block (stored in `total-erosion`)
- **Classical LS erosion** (`patch-g`) and **CN-weighted LS_CN erosion** (`patch-g2`) stored per patch
- **Spatial difference maps**: LS – LS_CN per cell for heterogeneity analysis
- **Bimodal distribution** parameters extracted from difference maps (used to quantify stripe effectiveness)

### Output Files

| File | Content |
|------|---------|
| `erosion_*.asc` | Spatial erosion rasters (LS and LS_CN) |
| `summary.csv` | Mean erosion per scenario configuration |
| `ls_comparison.csv` | Paired LS vs LS_CN statistics per block |
| `difference_*.asc` | Spatial LS – LS_CN difference rasters |
