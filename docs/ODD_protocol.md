# ODD Protocol: Agent-Based Model for Crop Pattern Effects on Soil Erosion

---

## 1. Purpose and Patterns

### 1.1 Purpose
The model simulates **water-driven soil erosion** on agricultural hillslopes to quantify how **spatial arrangement of crops** (uniform vs. striped patterns) affects erosion rates. The model integrates:

- **Topographic flow routing** (multiple flow direction algorithm)
- **Runoff generation** (USLE Curve Number method)
- **Erosion calculation** (modified USLE with CN-adjusted LS factor)

The primary research question: *Does accounting for runoff redistribution between crop strips with different CN values improve LS factor estimation compared to classical USLE?*

### 1.2 Patterns
The model reproduces:
- **Flow accumulation patterns** matching hydrological connectivity on real hillslopes
- **Erosion hotspots** at slope breaks and convergent areas
- **Differential erosion rates** between uniform and striped crop arrangements (observed in field studies)

---

## 2. Entities, State Variables, and Scales

### 2.1 Entities
The model contains two types of entities:

1. **Patches** (grid cells) – represent spatial units of the hillslope  
2. **Turtles** (mobile agents) – represent water flow parcels moving downslope

### 2.2 State Variables

#### Patch variables

| Variable | Description | Unit | Source |
|-----------|-------------|------|--------|
| `patch-elevation` | Elevation | m | DEM (ASC file) |
| `patch-slope-per` | Slope gradient (rise/run) | – | Computed (Horn 1981) |
| `patch-slope-deg` | Slope angle | degrees | Computed |
| `patch-aspect` | Aspect (azimuth) | degrees | Computed |
| `patch-k` | USLE K factor (soil erodibility) | t·ha·h/(ha·MJ·mm) | Soil type (0.33 Cambisol, 0.41 Chernozem) |
| `patch-c` | USLE C factor (crop cover) | – | ASC file or crop database |
| `patch-r` | USLE R factor (rainfall erosivity) | MJ·mm/(ha·h·yr) | Fixed 40 |
| `patch-p` | USLE P factor (support practice) | – | Fixed 1 |
| `patch-cn` | Curve Number | – | ASC file or crop database |
| `flow-acc` | Flow accumulation (contributing area) | cells | Computed (MFD) |
| `flows` | Flow fractions to 8 neighbors | list [8] | Computed (MFD) |
| `cnmod` | CN-based runoff ratio modifiers | list | Computed (WF mode) |
| `cn-ratio-base-sum` | Cumulative baseline CN modifier | – | Computed (WF mode) |
| `cn-ratio-sum` | Cumulative current CN modifier | – | Computed (WF mode) |
| `patch-g` | Soil loss (classical USLE) | t/(ha·yr) | Computed |
| `patch-g2` | Soil loss (CN‑modified USLE) | t/(ha·yr) | Computed |
| `noflow?` | No‑outflow cell (plateau/sink) | boolean | Computed |
| `drain?` | Boundary/outlet cell | boolean | Computed |
| `inner-land?` | Interior cell (≥ 5 cells from edge) | boolean | Computed |

#### Turtle variables

| Variable | Description | Unit |
|-----------|-------------|------|
| `frac` | Flow fraction carried by turtle | – |
| `cn-modifier` | Current scenario CN modifier | – |
| `cn-modifier-base` | Baseline scenario CN modifier | – |

#### Global variables

| Variable | Description |
|-----------|-------------|
| `elevation` | DEM dataset (GIS raster) |
| `dmr-res` | DEM resolution (cell size m) |
| `srazky-mm` | Rainfall depth (mm) – user input |
| `unique-CN` | List of unique CN values in landscape |
| `base-CN` | Current baseline CN for comparison |
| `plodiny-parametry` | Crop parameter database (C, CN values) |
| `total-erosion` | Mean erosion rate (t/ha/yr) |

### 2.3 Scales
- **Spatial extent:** 100–300 m hillslopes  
- **Spatial resolution:** 5 × 5 m cells  
- **Temporal resolution:** Single rainfall event (event‑based)  
- **Simulation duration:** One step (setup → flow routing → erosion)

---

## 3. Process Overview and Scheduling

### Phase 1 – Setup (`setup`)
1. Load and rescale DEM  
2. Compute slope and aspect (Horn algorithm)  
3. Identify boundary and no‑flow cells  
4. Load C and CN factors from ASC or assign by crop  
5. Set USLE factors: K (from soil), R = 40, P = 1  

### Phase 2 – Flow routing (`get-flow-accumulation`)
- **Prepare flows:** MFD weights computed from elevation differences  
- **Classical mode (WF? = false):** turtles carry flow share and build `flow-acc`  
- **CN‑modified mode (WF? = true):** turtles additionally carry CN ratios (`cn-modifier`, `cn-modifier-base`) and accumulate them downslope  

### Phase 3 – Erosion calculation (`calculate-erosion`)
- **Classical USLE:** `G = R × K × LS × C × P` using `flow-acc`  
- **CN‑modified USLE:** same but LS uses `flow‑acc × CN modifier`  
- Outputs mean erosion (`total‑erosion`)

---

## 4. Design Concepts

### 4.1 Basic Principles
The model couples:
- USLE (Wischmeier & Smith 1978),
- CN method (USDA‑SCS 1972),
- MFD flow routing (Desmet & Govers 1996).

Its novelty lies in modifying LS by propagated runoff ratios between crop strips.

### 4.2–4.11 Highlights
- **Emergence:** flow convergence → hotspots  
- **Adaptation:** none (deterministic)  
- **Sensing:** patches read local neighbors; turtles sense downslope elevation  
- **Interaction:** turtles deposit flow and CN ratios on patches  
- **Stochasticity:** none  
- **Collectives:** `land`, `inner‑land`, `sink` patch‑sets  
- **Observation:** maps of `flow‑acc`, `patch‑g/g2`, and aggregate `total‑erosion`

---

## 5. Initialization

### 5.1 Initial State
At `t = 0`: all patches `flow‑acc = 1`, `balance = 0`; `drain?` and `noflow?` set; no turtles exist.

### 5.2 Input Data
1. DEM (ASC)  
2. C‑factor map (ASC, 1 = crop1, 2 = crop2)  
3. CN map (optional ASC or derived from crop table)

### 5.3 Parameters

| Parameter | Description | Default | Range |
|-----------|-------------|----------|-------|
| `srazky-mm` | Rainfall depth | 50 mm | 10–200 |
| `soil` | Soil type | "kambizem" | "černozem", "kambizem" |
| `crop1`, `crop2` | Crop types | "pšenice ozimá", "kukuřice na zrno" | 20 types |
| `division` | Crop pattern | "stripes" | "single", "two", "stripes", "one110" |
| `division_angle` | Stripe orientation | 0° | 0–135° |
| `stripe-length` | Stripe width | 20 m | 10–110 |
| `WF?` | Curve Number‑modified approach on/off | true | true/false |
| `par-minfrac` | Min flow fraction threshold | 0.001 | 0–0.1 |

---

## 6. Input Data
Static spatial inputs only (no time‑series).

---

## 7. Submodels

### 7.1 Slope and Aspect (`update-slope-and-aspect`)

Horn (1981):

\[
\begin{aligned}
dz/dx &= \frac{(c + 2f + i) - (a + 2d + g)}{8\,Δx} \\
dz/dy &= \frac{(g + 2h + i) - (a + 2b + c)}{8\,Δy} \\
slope &= \sqrt{(dz/dx)^2 + (dz/dy)^2} \\
aspect &= \arctan(-dz/dx,\,dz/dy)
\end{aligned}
\]

---

### 7.2 Flow Direction Partitioning (`prepare-flows`)
Multiple Flow Direction (MFD):
1. Compute Δz to neighbors > 0  
2. Weight by distance (0.5 cardinal, 0.354 diagonal)  
3. Normalize: `flow_fraction = s_i / Σs`  
4. Apply small‑slope threshold (`turning point ≈ 0.3–0.5 × slope`).

---

### 7.3 CN‑Based Runoff Ratio (`get-CN-modifier`)
\[
S = \frac{25400 - 254\,CN}{CN}
\]
If \(P ≤ 0.2S → R=0;\) else  
\[
R = \frac{(P - 0.2S)^2}{P + 0.85S}
\]
Runoff ratio \(= R_{current}/R_{baseline}\).

---

### 7.4 Flow Accumulation (`turtles‑move‑forward`)
Recursive turtle movement adds `frac` to `flow‑acc` and sums CN‑modifiers until no turtles remain.

---

### 7.5 LS Factor (`usle‑base‑g`, `usle‑base‑g2`)
Desmet & Govers (1996):

\[
\begin{aligned}
β &= \frac{\sin θ}{0.0896(3\,\sin^{0.8}θ + 0.56)} \\
L &= \left[\frac{A}{22.13\,Δx(|\sin φ| + |\cos φ|)}\right]^{β/(β+1)} \\
S &= -1.5 + \frac{17}{1 + e^{2.3 - 6.1\,\sin θ}}
\end{aligned}
\]

where A = `flow‑acc` (classical) or `flow‑acc × CN modifier` (modified).

---

### 7.6 Erosion
\[
G = R \times K \times LS \times C \times P
\]
For CN‑modified mode, LS uses A modified by CN ratio.

---

**Note:** All references cited in this appendix are included in the main manuscript reference list.
