# uslecn-abm-erosion
# Reducing homogeneity bias in LS topographic factors: LS_CN: a parsimonious modification for heterogeneous agricultural landscapes

## Overview

This repository contains code and materials to reproduce the analyses presented in:

**Bednář, M., Šarapatka, B.** (2026). Reducing homogeneity bias in LS topographic factors: LS_CN: a parsimonious modification for heterogeneous agricultural landscapes *Environmental Modelling & Software* [in review].

## Abstract

Classical LS-factor estimation in USLE-type models often fail in heterogeneous agricultural landscapes because the topographic logic assumes uniform runoff generation across contributing areas. We propose LS_CN, a data-light modification that weights flow accumulation by Curve Number (CN)-derived runoff ratios to account for land-use-driven runoff variability without additional calibration. The method was implemented in an agent-based framework and tested on over 20,000 synthetic and real-world scenarios with contrasting crop configurations and event rainfall depths. Results show that classical LS systematically misestimates effective contributing areas, while LS_CN reduces this 'homogeneity bias' and leads to 15–30% lower, yet more process-consistent, soil loss predictions. We identified a critical sensitivity window at rainfall depths of 40–70 mm where CN-weighting most significantly alters erosion risk patterns. LS_CN provides a practical, computationally efficient tool for evaluating nature-based solutions (e.g., strip cropping, buffer zones) where the spatial configuration of runoff pathways drives erosion risk.

## Repository Contents
```
├── README.md                          # This file
├── python/
│   ├── generate_synthetic_dems.py    # Script for creating virtual terrain models
│   ├── generate_landuse.py           # Script for creating crop strip patterns
│   └── requirements.txt              # Python dependencies
├── netlogo/
│   ├── usle_abm_model.nlogo          # NetLogo ABM implementation
│   └── README.md                     # Instructions for running NetLogo model
├── data/
│   ├── real_blocks/                  # Links to public Czech DEM data
│   └── example_outputs/              # Sample output files
├── docs/
│   ├── ODD_protocol.md               # Detailed model description
│   └── parameters.md                 # Parameter values used in simulations
└── LICENSE                           # MIT or CC-BY-4.0
```

## Requirements

### Python Environment
- Python 3.8+
- numpy
- matplotlib
- (see `python/requirements.txt` for complete list)

### NetLogo
- NetLogo 6.4 or higher
- Download from: https://ccl.northwestern.edu/netlogo/

## Quick Start

### 1. Generate Synthetic DEMs
```bash
cd python
python generate_synthetic_dems.py
```

This creates 9 synthetic terrain models (3 surface shapes × 3 flow patterns) 
in the `output/dems/` directory.

### 2. Generate Land-Use Patterns
```bash
python generate_landuse.py --strip-width 50 --orientation 90
```

### 3. Run ABM Simulations

1. Open `netlogo/usle_abm_model.nlogo` in NetLogo 6.4
2. Load generated DEM and land-use files
3. Set parameters according to `docs/parameters.md`
4. Run simulation

See `netlogo/README.md` for detailed instructions.

## Data Sources

### Synthetic Data
All synthetic DEMs and land-use patterns are generated using the provided scripts.

### Real Terrain Data
Real-world digital terrain models (DMR 4G, 5×5m resolution) were obtained from 
the Czech Office for Surveying, Mapping and Cadastre (ČÚZK):
- https://geoportal.cuzk.cz/

Due to licensing, these data are not included in this repository but can be 
freely downloaded from the above source.

## Key Parameters

### Terrain Generation
- Resolution: 5×5 m
- Block size: 600×600 m (120×120 pixels)
- Elevation range: 543–600 m
- Surface types: plane, convex, concave
- Flow patterns: parallel, divergent, convergent

### Strip Cropping Scenarios
- Strip widths: 25–250 m
- Orientations: 0–90° (relative to contour)
- Crops: maize (Zea mays) vs. cereals (Triticum)
- Soil types: Chernozems, Cambisols
- Rainfall depths: 30–120 mm

See `docs/parameters.md` for complete parameter specifications.

## Reproducibility

All analyses in the manuscript can be reproduced using:
1. The Python scripts to generate input data
2. The NetLogo model to run simulations
3. Parameter values specified in `docs/parameters.md`

**Note:** Due to the large number of scenarios (thousands of combinations), 
complete output datasets are not archived. However, all analyses are fully 
reproducible using the provided code.

## Citation

If you use this code in your research (if it is accepted for publishing), please cite:
```bibtex
@article{bednar2025usle,
  author = {Bednář, M. and Šarapatka, B.},
  title = {Reducing homogeneity bias in LS topographic factors: LS_CN: a parsimonious modification for heterogeneous agricultural landscapes},
  journal = {Environmental Modelling & Software},
  year = {2026},
  note = {in review}
}
```

## License

This code is released under the MIT License (see LICENSE file).

The manuscript and associated data are licensed under CC-BY-4.0.

## Contact

**Corresponding Author:** Bednář, M.  
**Institution:** Department of Ecology and Environmental Sciences, 
                Palacký University in Olomouc, Czech Republic  
**Email:** [marek.bednar@upol.cz]

## Acknowledgments

This work was supported by the Technology Agency of the Czech Republic (TAČR):
- Project SS02030018: Centre for Landscape and Biodiversity
- Project SS06010290: Strip cropping management as an adaptation measure to 
  optimize landscape water management

## Related Resources

- [NetLogo Documentation](https://ccl.northwestern.edu/netlogo/docs/)
- [USLE/RUSLE Resources](https://www.ars.usda.gov/research/rusle/)
- [Czech National Erosion Methodology](https://www.vumop.cz/)
```

---

## Dodatečné soubory:

### `python/requirements.txt`:
```
numpy>=1.20.0
matplotlib>=3.3.0
