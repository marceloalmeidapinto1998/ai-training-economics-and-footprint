USE EpochAI_DW;
GO

/* ============================================================================
   GOLD LAYER: UNIFIED FINOPS, ESG & FRONTIER CAPABILITY SEMANTIC VIEW
   Joins: fact_modelos_ia + base dimensions + Silver enriched dimensions
   ============================================================================ */

IF OBJECT_ID('dbo.vw_models_enriched', 'V') IS NOT NULL
    DROP VIEW dbo.vw_models_enriched;
GO

CREATE VIEW dbo.vw_models_enriched AS
WITH BenchmarkDedup AS (
    -- Deduplicate benchmarks per normalized model name to avoid row fan-out
    SELECT
        LOWER(LTRIM(RTRIM(COALESCE(Display_Name, Model_Group, Model_Version)))) AS norm_name,
        MAX(GPQA_Diamond_Score) AS GPQA_Diamond_Score,
        MAX(FrontierMath_Score) AS FrontierMath_Score,
        MAX(SWE_Bench_Score)    AS SWE_Bench_Score,
        MAX(MMLU_Score)         AS MMLU_Score,
        MAX(WebDev_Arena_Elo)   AS WebDev_Arena_Elo,
        MAX(Composite_Index)    AS Composite_Capability_Index
    FROM dbo.Dim_Model_Benchmarks
    GROUP BY LOWER(LTRIM(RTRIM(COALESCE(Display_Name, Model_Group, Model_Version))))
),
HardwareSpecsDedup AS (
    -- Map chip family names cleanly to official Epoch AI hardware specs
    SELECT
        LOWER(LTRIM(RTRIM(Hardware_Name))) AS norm_hw,
        MAX(TDP_Watts)          AS Official_TDP_Watts,
        MAX(Peak_BF16_TFLOPS)   AS Peak_BF16_TFLOPS,
        MAX(Peak_FP8_TFLOPS)    AS Peak_FP8_TFLOPS,
        MAX(Memory_GB)          AS Memory_GB,
        MAX(Est_Unit_CapEx_USD) AS Est_Unit_CapEx_USD
    FROM dbo.Dim_Hardware_Specs
    GROUP BY LOWER(LTRIM(RTRIM(Hardware_Name)))
)
SELECT
    -- 1. Core Model Identifiers & Governance Metadata
    f.model_id,
    f.model_name,
    f.organization,
    f.org_category,
    f.publication_date,
    f.publication_year,
    f.domain,
    f.accessibility,
    f.open_weights,
    f.frontier_model,

    -- 2. Compute & Scaling Telemetry
    f.parameters,
    f.training_compute_flop,
    f.log10_flop,
    f.hardware_quantity,
    f.training_time_hours,

    -- 3. Hardware Telemetry (Legacy + Official Epoch AI Specs)
    hw.chip_family,
    hw.manufacturer AS chip_manufacturer,
    COALESCE(hws.Official_TDP_Watts, CAST(hw.tdp_watts AS FLOAT)) AS tdp_watts,
    hws.Peak_BF16_TFLOPS,
    hws.Peak_FP8_TFLOPS,
    hws.Memory_GB,
    hws.Est_Unit_CapEx_USD,

    -- 4. Regional Grid, Carbon, Tariff & Water Cooling (WUE / PUE)
    COALESCE(p.country, 'Unknown') AS primary_country,
    g.Region_Code AS grid_region_code,
    COALESCE(g.Carbon_gCO2_kWh, p.gco2_per_kwh, 385.0) AS carbon_gco2_kwh,
    COALESCE(g.Tariff_USD_MWh, p.industrial_tariff_usd_kwh * 1000.0, 82.0) AS tariff_usd_mwh,
    COALESCE(g.WUE_Liters_kWh, 1.80) AS wue_liters_kwh,
    COALESCE(g.Default_Facility_PUE, 1.20) AS facility_pue,

    -- 5. Physics-Adjusted Energy, Carbon & Water Footprint (ESG Layer)
    f.total_energy_mwh AS it_energy_mwh,
    ROUND(f.total_energy_mwh * COALESCE(g.Default_Facility_PUE, 1.20), 2) AS facility_total_energy_mwh,
    ROUND((f.total_energy_mwh * COALESCE(g.Default_Facility_PUE, 1.20)) / 10.5, 1) AS eq_us_households_year,
    ROUND(
        (f.total_energy_mwh * COALESCE(g.Default_Facility_PUE, 1.20) * 1000.0 * COALESCE(g.Carbon_gCO2_kWh, p.gco2_per_kwh, 385.0)) / 1e6,
        2
    ) AS pue_adjusted_co2_tons,
    ROUND(
        (f.total_energy_mwh * COALESCE(g.Default_Facility_PUE, 1.20) * 1000.0 * COALESCE(g.WUE_Liters_kWh, 1.80)) / 1e6,
        4
    ) AS water_footprint_megaliters,

    -- 6. FinOps Economics (CapEx vs. OpEx Breakdown)
    f.total_cost_usd,
    f.electricity_cost_usd AS it_electricity_cost_usd,
    ROUND(
        f.total_energy_mwh * COALESCE(g.Default_Facility_PUE, 1.20) * COALESCE(g.Tariff_USD_MWh, p.industrial_tariff_usd_kwh * 1000.0, 82.0),
        2
    ) AS facility_electricity_cost_usd,
    CASE
        WHEN f.total_cost_usd IS NOT NULL AND f.electricity_cost_usd IS NOT NULL
        THEN ROUND(f.total_cost_usd - f.electricity_cost_usd, 2)
        ELSE NULL
    END AS hardware_infra_cost_usd,

    -- 7. Frontier Benchmarks & Efficiency ROI Metrics
    bm.GPQA_Diamond_Score,
    bm.FrontierMath_Score,
    bm.SWE_Bench_Score,
    bm.MMLU_Score,
    bm.WebDev_Arena_Elo,
    bm.Composite_Capability_Index,
    CASE
        WHEN bm.Composite_Capability_Index > 0 AND f.total_cost_usd > 0
        THEN ROUND(f.total_cost_usd / bm.Composite_Capability_Index, 2)
        ELSE NULL
    END AS usd_per_capability_point,
    CASE
        WHEN bm.Composite_Capability_Index > 0 AND f.total_energy_mwh > 0
        THEN ROUND(
            ((f.total_energy_mwh * COALESCE(g.Default_Facility_PUE, 1.20) * 1000.0 * COALESCE(g.Carbon_gCO2_kWh, p.gco2_per_kwh, 385.0)) / 1e6)
            / bm.Composite_Capability_Index,
            4
        )
        ELSE NULL
    END AS co2_tons_per_capability_point

FROM dbo.fact_modelos_ia f
LEFT JOIN dbo.dim_hardware hw
    ON f.hardware_id = hw.hardware_id
LEFT JOIN HardwareSpecsDedup hws
    ON LOWER(LTRIM(RTRIM(hw.chip_family))) = hws.norm_hw
LEFT JOIN dbo.dim_pais_energia p
    ON f.pais_id = p.pais_id
LEFT JOIN dbo.Dim_Grid_Enriched g
    ON (
        (p.country LIKE '%United States%' AND g.Region_Code = 'US-VA') OR
        (p.country LIKE '%China%' AND g.Region_Code = 'CN-EAST') OR
        (p.country LIKE '%United Kingdom%' AND g.Region_Code = 'UK-LON') OR
        (p.country LIKE '%Germany%' AND g.Region_Code = 'EU-DE') OR
        (p.country LIKE '%Sweden%' AND g.Region_Code = 'SE-NORD') OR
        (p.country LIKE '%Canada%' AND g.Region_Code = 'CA-QC')
    )
LEFT JOIN BenchmarkDedup bm
    ON LOWER(LTRIM(RTRIM(f.model_name))) = bm.norm_name;
GO

-- Quick verification sample from Gold Layer
SELECT TOP 10
    model_name,
    organization,
    publication_year,
    facility_total_energy_mwh,
    water_footprint_megaliters,
    pue_adjusted_co2_tons,
    Composite_Capability_Index,
    usd_per_capability_point
FROM dbo.vw_models_enriched
WHERE facility_total_energy_mwh IS NOT NULL
ORDER BY facility_total_energy_mwh DESC;
GO
