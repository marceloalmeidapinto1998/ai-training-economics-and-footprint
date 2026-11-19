# Data Sources, Physics Equations & FinOps Methodology

This document details the data lineage, thermodynamic/electrical equations, FinOps cost modeling assumptions, and data governance rules implemented in the **`EpochAI_DW`** SQL Server Medallion Data Warehouse and exported to `data/02_gold_exports/models_enriched_gold.csv`.

---

## 1. Primary Data Sources & Lineage

| Layer / Table | Source Dataset | Scope & Granularity | Primary Citations |
| :--- | :--- | :--- | :--- |
| **`fact_ai_models`** (`dbo.stg_epoch_models`) | **Epoch AI — Notable AI Models** | 1,102 notable & frontier ML models (training compute in FLOP, parameter counts, hardware quantities, training duration, reported power draw, and 2023 USD training cost). | Epoch AI (2024–2026), *Parameter, Compute and Data Trends in Machine Learning*. [epoch.ai/data/notable-ai-models](https://epoch.ai/data/notable-ai-models) |
| **`dim_hardware` & `dim_hardware_specs`** (`dbo.stg_epoch_hardware`) | **Epoch AI — ML Hardware Telemetry** | 153 physical GPU/TPU accelerators (Thermal Design Power `tdp_watts`, peak BF16/FP8 TFLOPS, HBM memory capacity `memory_gb`, and release CapEx `est_unit_capex_usd`). | Epoch AI (2024–2026), *Machine Learning Hardware Dataset*. [epoch.ai/data/machine-learning-hardware](https://epoch.ai/data/machine-learning-hardware) |
| **`dim_country_energy` & `dim_grid_enriched`** (`dbo.stg_grid_intensity_wue`) | **Regional Electricity Grids & Cooling Benchmarks** | 7 major AI training hubs (`US-VA`, `CN-EAST`, `UK-LON`, `EU-DE`, `SE-NORD`, `CA-QC`, plus global fallback) with grid carbon intensity ($\text{gCO}_2\text{/kWh}$), industrial electricity tariffs ($\text{USD/MWh}$), Water Usage Effectiveness (`wue_liters_kwh`), and facility `default_facility_pue`. | Ember / Our World in Data (OWID) Electricity Data; US EPA eGRID; Mytton (2021) *Data centre water consumption* (*npj Clean Water*). |
| **`dim_model_benchmarks`** (`dbo.stg_bench_*`) | **Epoch AI — Capabilities & Benchmarking Archive** | 534 evaluated frontier models consolidated across **GPQA Diamond**, **FrontierMath**, **SWE-Bench Verified**, **MMLU**, and **WebDev Arena** into a normalized `composite_index` ($0\text{--}100$). | Epoch AI Benchmarking Archive. [epoch.ai/data/ai-benchmarking-dashboard](https://epoch.ai/data/ai-benchmarking-dashboard) |

---

## 2. Physics & Environmental (ESG) Equations

All energy, water, and carbon metrics are computed in the Silver (`warehouse/02_silver_transform/build_fact_models.sql`) and Gold (`warehouse/03_gold_marts/vw_models_enriched.sql`) layers using standard data center thermodynamic principles.

### 2.1 Power Draw Imputation (`estimated_power_watts`)
When direct cluster power draw (`Training_power_draw_W`) is disclosed by the model authors, that value is preserved. Otherwise, IT cluster power draw is imputed from accelerator count ($N_{\mathrm{chips}}$), chip Thermal Design Power ($\mathrm{TDP}_{\mathrm{W}}$), and an empirical sustained training utilization factor ($\eta_{\mathrm{load}} = 0.85$):

$$
P_{\mathrm{IT\,(W)}} = \begin{cases} P_{\mathrm{reported}} & \text{if disclosed} \\ N_{\mathrm{chips}} \times \mathrm{TDP}_{\mathrm{W}} \times 0.85 & \text{otherwise} \end{cases}
$$

### 2.2 IT vs. Facility-Adjusted Energy (`it_energy_mwh` & `facility_total_energy_mwh`)

- **IT Cluster Energy (`it_energy_mwh`):** Incorporates a baseline hyperscale Power Usage Effectiveness ($\mathrm{PUE}_{\mathrm{base}} = 1.15$) over total training hours ($t_{\mathrm{hours}}$):

$$
E_{\mathrm{IT\,(MWh)}} = \frac{P_{\mathrm{IT\,(W)}} \times t_{\mathrm{hours}}}{10^6} \times 1.15
$$

- **Regional Facility-Adjusted Energy (`facility_total_energy_mwh`):** Scales IT energy by the regional data center PUE (`default_facility_pue` from `dim_grid_enriched`, defaulting to $1.20$ when regional mapping is unknown):

$$
E_{\mathrm{facility\,(MWh)}} = E_{\mathrm{IT\,(MWh)}} \times \mathrm{PUE}_{\mathrm{region}}
$$

### 2.3 Carbon Emissions (`pue_adjusted_co2_tons`)
Total metric tons of $\mathrm{CO}_2$ equivalent emitted during training are derived from facility electricity consumption and regional grid carbon intensity ($I_{\mathrm{grid}}$ in $\mathrm{gCO}_2\mathrm{/kWh}$):

$$
\mathrm{CO}_2\mathrm{\ (metric\ tons)} = \frac{E_{\mathrm{facility\,(MWh)}} \times 1,000 \times I_{\mathrm{grid}}}{10^6}
$$

### 2.4 Evaporative Water Footprint (`water_footprint_megaliters`)
On-site cooling tower water consumption in Megaliters ($1\text{ ML} = 10^6\text{ Liters}$) is estimated using regional Water Usage Effectiveness ($\mathrm{WUE}$ in $\mathrm{Liters/kWh}$, fallback $1.80\text{ L/kWh}$):

$$
W_{\mathrm{cooling\,(ML)}} = \frac{E_{\mathrm{facility\,(MWh)}} \times 1,000 \times \mathrm{WUE}_{\mathrm{region}}}{10^6}
$$

---

## 3. FinOps & Frontier Capability ROI Formulas

### 3.1 Electricity OpEx vs. Hardware Infrastructure CapEx

- **IT Electricity Bill (`electricity_cost_usd`):**

$$
\mathrm{OpEx}_{\mathrm{IT\,(USD)}} = E_{\mathrm{IT\,(MWh)}} \times 1,000 \times \mathrm{Tariff}_{\mathrm{USD/kWh}}
$$

- **Facility Electricity Bill (`facility_electricity_cost_usd`):**

$$
\mathrm{OpEx}_{\mathrm{facility\,(USD)}} = E_{\mathrm{facility\,(MWh)}} \times \mathrm{Tariff}_{\mathrm{USD/MWh}}
$$

- **Amortized Hardware & Cluster Infrastructure (`hardware_infra_cost_usd`):**

$$
\mathrm{CapEx}_{\mathrm{infra\,(USD)}} = \mathrm{TotalCost}_{\mathrm{USD}} - \mathrm{ElectricityCost}_{\mathrm{USD}}
$$

*(Enforced in Silver so `total_cost_usd >= electricity_cost_usd` whenever total compute cost is disclosed.)*

### 3.2 Normalized Capability Index & ROI Metrics
The **`composite_index`** (`0–100`) averages available normalized scores across four frontier evaluations (`gpqa_diamond_score`, `frontiermath_score`, `swe_bench_score`, `mmlu_score`), enabling standardized efficiency ratios in `vw_models_enriched`:

$$
\mathrm{USD\ per\ Capability\ Point} = \frac{\mathrm{TotalCost}_{\mathrm{USD}}}{\mathrm{CompositeCapabilityIndex}}
$$

$$
\mathrm{CO}_2\mathrm{\ Tons\ per\ Capability\ Point} = \frac{\mathrm{PUEAdjustedCO2}_{\mathrm{tons}}}{\mathrm{CompositeCapabilityIndex}}
$$

---

## 4. Automated Data Quality Governance (`data_quality_assertions.sql`)

Before exporting the Gold Mart (`models_enriched_gold.csv`), `warehouse/04_tests/data_quality_assertions.sql` validates six automated assertions (`6/6 PASS`):
1. `fk_integrity_hardware`: Zero orphaned `hardware_id` keys between `fact_ai_models` and `dim_hardware`.
2. `fk_integrity_country_energy`: Zero orphaned `country_id` keys between `fact_ai_models` and `dim_country_energy`.
3. `physical_bounds_pue`: All `default_facility_pue` values in `dim_grid_enriched` lie within $[1.02, 2.50]$.
4. `physical_bounds_hardware_tdp`: All `tdp_watts` values in `dim_hardware_specs` lie within $(0, 10000]$.
5. `finops_cost_consistency`: Disclosed `total_cost_usd` is always $\ge$ `electricity_cost_usd`.
6. `gold_view_non_empty`: `dbo.vw_models_enriched` returns active records ($> 0$ rows).