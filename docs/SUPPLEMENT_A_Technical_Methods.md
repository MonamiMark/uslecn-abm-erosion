# Supplement A: Technical Methods

This supplement provides mathematical details and computational procedures extracted from the main Methods section (Sections 2.2 and 2.3). It is designed to be self-contained: readers can understand all mathematical formulations and derivations without returning to the main text. Main text sections reference specific subsections here (e.g., "see Supplement A.1.2") for readers seeking detailed equations.

## Contents

1. LS_CN Curve-Number Integration (from Section 2.2)
2. Topographic Factor Computation (from Section 2.3)
3. Multiple Flow Direction Algorithm (from Section 2.3)

---

## A.1 LS_CN Curve-Number Integration

### A.1.1 Classical LS Equation in USLE

The Universal Soil Loss Equation (USLE) estimates long-term average annual soil loss as:

$$A = R \times K \times LS \times C \times P$$

where:
- **A** = computed soil loss per unit area (Mg·ha⁻¹·year⁻¹)
- **R** = rainfall erosivity factor (MJ·mm·ha⁻¹·h⁻¹·year⁻¹)
- **K** = soil erodibility factor (Mg·ha⁻¹·h⁻¹·MJ⁻¹·mm⁻¹)
- **LS** = topographic factor (dimensionless) — combined slope length (L) and slope steepness (S)
- **C** = cover-management factor (dimensionless, 0 ≤ C ≤ 1)
- **P** = support practice factor (dimensionless, 0 ≤ P ≤ 1)

The topographic factor LS is computed as:

$$LS = L \times S$$

where L and S are computed from the Digital Elevation Model (DEM) and represent how topography modulates erosion risk across landscapes. The classical approach assumes that all upslope contributing area drains equally regardless of land cover, creating a "homogeneity bias" in fragmented landscapes.

### A.1.2 Infiltration-Weighted Modification: CN Integration

The SCS Curve Number (CN) method estimates rainfall runoff as a function of precipitation, land use, and soil type. For a rainfall event, the runoff depth Q is:

$$Q = \begin{cases}
0 & \text{if } P_{\text{rain}} \leq I_a \\
\frac{(P_{\text{rain}} - I_a)^2}{P_{\text{rain}} - I_a + S} & \text{if } P_{\text{rain}} > I_a
\end{cases}$$

where:
- **P_rain** = rainfall depth (mm)
- **I_a** = initial abstraction (mm), typically I_a = 0.2S
- **S** = maximum soil retention (mm) = 25,400/CN − 254

The **CN value** ranges from 0 to 100, where:
- Lower CN values (e.g., CN = 55) indicate high infiltration capacity and low runoff propensity (e.g., grassland on sandy soil)
- Higher CN values (e.g., CN = 80) indicate low infiltration capacity and high runoff propensity (e.g., bare soil or impervious surfaces)

The LS_CN modification weights flow accumulation by the runoff potential of each landscape patch, recognizing that 100 m² of high-infiltration grassland contributes less runoff than 100 m² of bare soil. The core equation is:

$$\text{LS}_{\text{CN}} = \text{LS} \times f(\text{CN})$$

where f(CN) is a runoff-based weighting function.

More specifically, we adjust the classical upslope contributing area (F_acc) using the ratio between:
- **Q_struct** = runoff from the actual heterogeneous hillslope (spatial mosaic of CN values)
- **Q_homo** = runoff from a hypothetical homogeneous surface (using the CN of the outlet cell)

$$\text{Correction Factor} = \frac{Q_{\text{struct}}}{Q_{\text{homo}}}$$

This ratio acts as a runoff-based correction of effective contributing area: when upslope pixels have lower CN (higher infiltration) than the outlet, the correction factor < 1, effectively reducing the slope-length factor at the outlet point.

### A.1.3 Implementation in Flow Accumulation

In implementation, the modified contributing area is computed as:

$$F_{\text{acc,mod}} = F_{\text{acc}} \times \frac{Q_{\text{struct}}}{Q_{\text{homo}}}$$

where:
- **F_acc** = classical contributing area (m²·m⁻¹), computed from DEM assuming homogeneous cover
- **F_acc,mod** = CN-weighted contributing area (m²·m⁻¹), adjusted for infiltration heterogeneity
- The ratio Q_struct/Q_homo is calculated for each cell based on its upslope CN configuration

The modified contributing area is then substituted into the L-factor formula actually implemented in the model (see Section A.2.1 for the full, aspect-corrected, variable-exponent form used in Supplement B / the ODD Protocol):

$$L_{\text{CN}} = \left(\frac{F_{\text{acc,mod}}}{22.13 \times D \times (|\sin\alpha| + |\cos\alpha|)}\right)^{m}, \quad m = \frac{\beta}{\beta+1}$$

where D is cell size (m), α is cell aspect, and m is the McCool et al. (1989) variable slope-length exponent (Section A.2.1) rather than a fixed value.

**Physical interpretation:** In heterogeneous landscapes (e.g., strip-cropped fields), high-infiltration patches (e.g., grass strips with CN = 55) reduce the effective downslope flow energy compared to erosion-prone row crops (e.g., maize, CN ≈ 66). The CN weighting captures this by reducing F_acc,mod where upslope infiltration is high. As a result, LS_CN produces lower erosion estimates than classical LS in fragmented landscapes with low-CN protective patches upslope, while converging to classical LS in homogeneous landscapes.

**Example:** Consider an outlet cell in maize (CN = 66), with an upslope area that is 50% maize (CN = 66) and 50% grass (CN = 55), giving a mosaic-average upslope CN ≈ 60.5. Using the SCS-CN runoff equation (Section A.1.2) with a representative rainfall depth of 70 mm:
- Reference case (homogeneous maize outlet crop, CN = 66): S = 25,400/66 − 254 ≈ 130.9 mm, I_a ≈ 26.2 mm, giving Q_homo ≈ 11.0 mm
- Actual upslope mosaic (average CN ≈ 60.5): S ≈ 165.8 mm, I_a ≈ 33.2 mm, giving Q_struct ≈ 6.7 mm
- Q_struct/Q_homo ≈ 0.61, so F_acc,mod ≈ 0.61 × F_acc

This reduction reflects that the upslope grass strip has higher infiltration capacity than the erosion-prone maize outlet, consistent with the qualitative direction described in Section 2.2.2 of the main text: upslope infiltration higher than the outlet's own reduces the effective contributing area.

---

## A.2 Topographic Factor Computation

### A.2.1 Slope-Length Factor (L)

The slope-length factor represents the cumulative effect of slope length on erosion. Following Desmet & Govers (1996), it is computed from the aspect-corrected unit contributing area as:

$$L = \left(\frac{F_{\text{acc}}}{22.13 \times D \times (|\sin\alpha| + |\cos\alpha|)}\right)^{m}, \quad m = \frac{\beta}{\beta+1}$$

where:
- **F_acc** = upslope contributing area (flow accumulation × cell area, m²)
- **D** = cell size (m; 5 m in this study)
- **22.13** = reference slope length (m) used in USLE standardization
- **α** = cell aspect (direction of steepest downslope flow); the term |sin α| + |cos α| corrects the unit contributing area for the orientation of flow relative to the grid axes (Desmet & Govers, 1996)
- **m** = slope-dependent slope-length exponent (dimensionless), following the McCool et al. (1989) revised formulation (not a fixed value):

$$\beta = \frac{\sin\theta}{0.0896 \times (3 \times \sin^{0.8}\theta + 0.56)}$$

where θ is the local slope angle. m increases from ≈0.2 on very gentle slopes toward ≈0.5–0.6 on steeper slopes, rather than being fixed at 0.5 throughout.

**Computation steps:**
1. Compute flow accumulation from the DEM using MFD (see Section A.3)
2. Flow accumulation gives the number of upslope cells draining to each cell
3. Multiply by cell area to get F_acc in m²
4. Compute β and m from the local slope angle, and α from the Horn (1981) aspect calculation (Section A.2.4)
5. Divide by the aspect-corrected reference length to obtain L

**Special cases:**
- At hilltops: F_acc ≈ 1 cell, so L ≈ 1 (no upstream influence)
- At valley bottoms: F_acc can be very large, so L >> 1 (strong upstream influence)

For LS_CN, the same formula applies but using F_acc,mod (CN-weighted contributing area) instead of classical F_acc.

### A.2.2 Slope-Steepness Factor (S)

The slope-steepness factor represents the effect of local slope gradient on detachment. Following Nearing (1997), it is computed as a single continuous function of slope angle (avoiding the discontinuity between separate low-slope and high-slope equations used in some USLE/RUSLE formulations):

$$S = -1.5 + \frac{17}{1 + \exp(2.3 - 6.1\sin\theta)}$$

where:
- **θ** = local slope angle (degrees), derived from the DEM using the Horn (1981) finite-difference method (Section A.2.4)

**Physical interpretation:**
- S is small and near its lower asymptote on flat-to-gentle terrain
- S increases non-linearly and more steeply through the mid-slope range
- At θ = 15°, S ≈ 4.1
- At θ = 30°, S ≈ 10.0
- S approaches its upper asymptote (≈15.1) on very steep terrain, avoiding the unbounded growth of simpler linear-in-sine formulations

**Computation:**
- For each cell, compute the slope in x and y directions using neighboring cells (Section A.2.4)
- Slope angle: θ = arctan(√(slope_x² + slope_y²))
- Substitute into the S formula above

This single continuous function is used throughout the model, replacing the separate low-slope/high-slope equations found in some USLE/RUSLE handbooks; it is the same formulation implemented in the NetLogo model (Supplement B, `usle-base-g`) and documented in the ODD Protocol (Section 3.3).

### A.2.3 L × S Interaction and Combined Effect

The combined topographic factor LS represents the integrated effect of slope length and steepness:

$$LS = L \times S$$

**Landscape implications:**

1. **Divergent flow patterns** (concave hillslopes): Flow disperses downslope, reducing local flow accumulation. Result: L decreases, LS decreases → lower erosion potential.

2. **Convergent flow patterns** (convex hollows): Flow concentrates into gullies and channels. Result: L increases locally, LS increases → higher erosion potential concentrated in specific flow paths.

3. **Interaction with slope gradient:**
   - Gentle slopes: S is small; LS is dominated by L (length effect)
   - Steep slopes: S is large; even moderate L values produce large LS (gradient effect dominates)

4. **Real-world heterogeneity:** Strip-cropping and buffer zones affect both L and S indirectly through their effect on flow routing. Protective strips can divert flow to less steep paths, effectively reducing local S. CN weighting captures this through modified F_acc,mod, which propagates into modified L values.

**Example calculation:**
- Cell with F_acc = 1,000 m² (flow accumulation of 40 cells × 25 m² at 5 m resolution), D = 5 m, aspect α = 0° (flow aligned with the grid axis, so |sin α| + |cos α| = 1):
  - Local slope angle θ = 10°: β = sin(10°) / (0.0896 × (3 × sin(10°)^0.8 + 0.56)) = 0.1736 / 0.1164 ≈ 1.49
  - m = β/(β+1) ≈ 1.49/2.49 ≈ 0.60 (compare to the fixed m = 0.5 used in some simplified USLE applications)
  - L = (1,000 / (22.13 × 5 × 1))^0.60 = (9.04)^0.60 ≈ 3.75
  - S = −1.5 + 17/(1 + exp(2.3 − 6.1 × sin(10°))) = −1.5 + 17/(1 + exp(1.24)) ≈ −1.5 + 3.81 ≈ 2.31
- Combined: LS ≈ 3.75 × 2.31 ≈ 8.7

### A.2.4 Slope and Aspect Computation (Horn's Algorithm)

Slope angle θ and aspect α are both derived from the DEM using the Horn (1981) 3×3 finite-difference window, as implemented in Supplement B (`update-slope-and-aspect`):

$$\frac{\partial z}{\partial x} = \frac{(z_{tr} + 2z_r + z_{br}) - (z_{tl} + 2z_l + z_{bl})}{8 \times D}, \quad \frac{\partial z}{\partial y} = \frac{(z_{bl} + 2z_b + z_{br}) - (z_{tl} + 2z_t + z_{tr})}{8 \times D}$$

$$\theta = \arctan\sqrt{\left(\frac{\partial z}{\partial x}\right)^2 + \left(\frac{\partial z}{\partial y}\right)^2}, \qquad \alpha = \arctan\left(-\frac{\partial z}{\partial x}, \frac{\partial z}{\partial y}\right)$$

where the subscripts denote the eight neighboring cells (t = top, b = bottom, l = left, r = right) and D is cell size. θ feeds into both the L-factor exponent m (Section A.2.1) and the S-factor (Section A.2.2); α feeds into the aspect-corrected unit contributing area in the L-factor (Section A.2.1).

---

## A.3 Multiple Flow Direction (MFD) Algorithm

### A.3.1 MFD vs. Single-Flow Methods

**Single-flow direction (SFD, e.g., D8):**
- All water from each cell is routed to the single steepest downslope neighbor
- Produces concentrated flow paths
- Advantage: Computationally simple
- Disadvantage: Overestimates flow concentration; creates unrealistic linear drainage networks

**Multiple flow direction (MFD, Quinn et al., 1991):**
- Water is distributed among all downslope neighbors proportionally to slope gradient
- Produces dispersed flow across the landscape
- Advantage: Better represents real water dispersal across complex terrain
- Disadvantage: Slightly more computationally intensive, but still very efficient

**Landscape relevance:** In heterogeneous agricultural landscapes, MFD better captures how runoff spreads across different infiltration zones (e.g., strip-cropping patterns) rather than concentrating on single paths. This is particularly important for evaluating Nature-Based Solutions where spatial configuration affects flow distribution.

### A.3.2 MFD Flow Distribution

For each cell (i, j) with multiple downslope neighbors, the flow distribution to neighbor k is:

$$\text{Flow}_{i,j \to k} = \text{Flow}_{i,j} \times \frac{\tan(\beta_{i,j \to k})}{\sum_{\text{all downslope}} \tan(\beta_{i,j \to m})}$$

where:
- **Flow_{i,j→k}** = proportion of flow routed from cell (i,j) to neighbor k
- **Flow_{i,j}** = total water arriving at cell (i,j) (from upslope accumulation)
- **β_{i,j→k}** = slope angle from cell (i,j) toward downslope neighbor k (radians)
- The denominator sums slope angles to all downslope neighbors

**Normalization:** The flow proportions sum to 1:

$$\sum_{\text{k downslope}} \text{Flow}_{i,j \to k} = 1$$

**Special cases:**
- Flat cells (no downslope neighbors): Flow is retained or routed to the nearest depression
- Sinks (local minima): Typically rare in agricultural DEMs but must be handled by filling or depression routing
- Ridge cells (all neighbors are upslope): No outflow

### A.3.3 Flow Accumulation with MFD

Flow accumulation is computed by processing cells in order from high to low elevation (topological sort):

**Algorithm:**

```
1. Sort all cells by elevation (highest first)
2. Initialize: accumulation[cell] = 1 for all cells (representing cell itself)
3. FOR each cell in sorted order (high → low):
     a. Find all downslope neighbors
     b. FOR each downslope neighbor:
          i. Compute flow proportion = tan(slope to neighbor) / sum(slopes to all downslope)
          ii. Transfer flow: accumulation[neighbor] += accumulation[cell] × flow_proportion
4. Output: accumulation map with values ≥ 1 per cell
```

**Physical interpretation:**
- Cells with accumulation = 1 are ridgetops (no upslope contributors)
- Cells with accumulation >> 1 are in valleys (many upslope contributors)
- Accumulation values represent the number of cells draining through each cell

**Computational complexity:**
- Sorting: O(n log n), where n = number of cells
- Accumulation loop: O(n × k), where k ≈ average number of downslope neighbors per cell (typically k ≈ 3–5)
- Total: O(n log n) for typical DEMs, which is efficient even for large rasters (10⁶–10⁷ cells)

**Application to LS_CN:**

For CN-weighted flow accumulation, the model does not apply a single per-cell CN weight inline during one accumulation pass; instead, for each unique CN class present in the landscape it performs two full MFD routing passes and takes the ratio of the results (matching the actual NetLogo implementation in Supplement B and the ODD Protocol, Section 1.3 step 4):

```
FOR each unique CN class c in the landscape:
  1. Reference pass: set all patches to the reference (uniform outlet) CN,
     route flow with MFD, accumulate cn-ratio-base-sum
  2. Actual pass: set all patches to their actual CN, route flow with MFD,
     accumulate cn-ratio-sum
  3. Compute the CN ratio for class c: cnmod[c] = cn-ratio-sum / cn-ratio-base-sum
Output: cnmod, one ratio per CN class, applied per patch according to its class
```

The resulting per-class ratio is then used in place of the classical contributing area when computing the L factor (using the same aspect-corrected, variable-exponent form as Section A.2.1):

$$L_{\text{CN}} = \left(\frac{F_{\text{acc}} \times \text{cnmod}}{22.13 \times D \times (|\sin\alpha| + |\cos\alpha|)}\right)^{m}$$

The S factor is identical to the classical formulation (Section A.2.2) — CN-weighting modifies only the contributing-area term, not the slope-steepness term.

**Key difference:** CN weighting reduces flow propagation through high-infiltration patches and increases it through low-infiltration patches, producing spatially explicit modification of L factors that reflects landscape heterogeneity.

---

## References

Desmet, P. J. J., & Govers, G. (1996). A GIS procedure for automatically calculating the USLE LS factor on topographically complex landscape units. Journal of Soil and Water Conservation, 51(5), 427–433.

Horn, B. K. P. (1981). Hill shading and the reflectance map. Proceedings of the IEEE, 69(1), 14–47.

McCool, D. K., Foster, G. R., Mutchler, C. K., & Meyer, L. D. (1989). Revised slope length factor for the Universal Soil Loss Equation. Transactions of the ASAE, 32(5), 1571–1576.

Mitasova, H., Hofierka, J., Zlocha, M., & Iverson, L. R. (1996). Modelling topographic potential for erosion and deposition using GIS. International Journal of Geographical Information Systems, 10(5), 629–641.

Nearing, M. A. (1997). A single, continuous function for slope steepness influence on soil loss. Soil Science Society of America Journal, 61(3), 917–919.

Quinn, P., Beven, K., Chevallier, P., & Planchon, O. (1991). The prediction of hillslope flow paths for distributed hydrological modelling using digital elevation models. Hydrological Processes, 5(1), 59–79.

USDA Soil Conservation Service. (1986). National Engineering Handbook, Section 4: Hydrology. Washington, DC: USDA SCS.

Wischmeier, W. H., & Smith, D. D. (1978). Predicting rainfall erosion losses: A guide to conservation planning. USDA Agriculture Handbook No. 537. Washington, DC: USDA SCS.
