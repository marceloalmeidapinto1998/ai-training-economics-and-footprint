USE EpochAI_DW;
GO

/* ============================================================================
   GOLD LAYER: UNIFIED FINOPS, ESG & FRONTIER CAPABILITY SEMANTIC VIEW
   Joins: fact_ai_models + base dimensions + Silver enriched dimensions
   ============================================================================ */

IF OBJECT_ID('dbo.vw_models_enriched', 'V') IS NOT NULL
    DROP VIEW dbo.vw_models_enriched;
GO

CREATE VIEW dbo.vw_models_enriched AS
WITH benchmark_dedup AS (
    SELECT
        LOWER(LTRIM(RTRIM(COALESCE(display_name, model_group, model_version)))) AS norm_name,
        MAX(gpqa_diamond_score) AS GPQA_Diamond_Score,
        MAX(frontiermath_score) AS FrontierMath_Score,
        MAX(swe_bench_score)    AS SWE_Bench_Score,
        MAX(mmlu_score)         AS MMLU_Score,
        MAX(webdev_arena_elo)   AS WebDev_Arena_Elo,
        MAX(composite_index)    AS Composite_Capability_Index
    FROM dbo.dim_model_benchmarks
    GROUP BY LOWER(LTRIM(RTRIM(COALESCE(display_name, model_group, model_version))))
),
hardware_specs_dedup AS (
    SELECT
        LOWER(LTRIM(RTRIM(hardware_name))) AS norm_hw,
        MAX(tdp_watts)          AS Official_TDP_Watts,
        MAX(peak_bf16_tflops)   AS Peak_BF16_TFLOPS,
        MAX(peak_fp8_tflops)    AS Peak_FP8_TFLOPS,
        MAX(memory_gb)          AS Memory_GB,
        MAX(est_unit_capex_usd) AS Est_Unit_CapEx_USD
    FROM dbo.dim_hardware_specs
    GROUP BY LOWER(LTRIM(RTRIM(hardware_name)))
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

    -- 3. Hardware Telemetry (Base + Official Epoch AI Specs)
    hw.chip_family,
    hw.manufacturer AS chip_manufacturer,
    COALESCE(hws.Official_TDP_Watts, CAST(hw.tdp_watts AS FLOAT)) AS tdp_watts,
    hws.Peak_BF16_TFLOPS,
    hws.Peak_FP8_TFLOPS,
    hws.Memory_GB,
    hws.Est_Unit_CapEx_USD,

    -- 4. Regional Grid, Carbon, Tariff & Water Cooling (WUE / PUE)
    COALESCE(p.country, 'Unknown') AS primary_country,
    g.region_code AS grid_region_code,
    COALESCE(g.carbon_gco2_kwh, p.gco2_per_kwh, 385.0) AS carbon_gco2_kwh,
    COALESCE(g.tariff_usd_mwh, p.industrial_tariff_usd_kwh * 1000.0, 82.0) AS tariff_usd_mwh,
    COALESCE(g.wue_liters_kwh, 1.80) AS wue_liters_kwh,
    COALESCE(g.default_facility_pue, 1.20) AS facility_pue,

    -- 5. Physics-Adjusted Energy, Carbon & Water Footprint (ESG Layer)
    f.total_energy_mwh AS it_energy_mwh,
    ROUND(f.total_energy_mwh * COALESCE(g.default_facility_pue, 1.20), 2) AS facility_total_energy_mwh,
    ROUND((f.total_energy_mwh * COALESCE(g.default_facility_pue, 1.20)) / 10.5, 1) AS eq_us_households_year,
    ROUND(
        (f.total_energy_mwh * COALESCE(g.default_facility_pue, 1.20) * 1000.0 * COALESCE(g.carbon_gco2_kwh, p.gco2_per_kwh, 385.0)) / 1e6,
        2
    ) AS pue_adjusted_co2_tons,
    ROUND(
        (f.total_energy_mwh * COALESCE(g.default_facility_pue, 1.20) * 1000.0 * COALESCE(g.wue_liters_kwh, 1.80)) / 1e6,
        4
    ) AS water_footprint_megaliters,

    -- 6. FinOps Economics (CapEx vs. OpEx Breakdown)
    f.total_cost_usd,
    f.electricity_cost_usd AS it_electricity_cost_usd,
    ROUND(
        f.total_energy_mwh * COALESCE(g.default_facility_pue, 1.20) * COALESCE(g.tariff_usd_mwh, p.industrial_tariff_usd_kwh * 1000.0, 82.0),
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
            ((f.total_energy_mwh * COALESCE(g.default_facility_pue, 1.20) * 1000.0 * COALESCE(g.carbon_gco2_kwh, p.gco2_per_kwh, 385.0)) / 1e6)
            / bm.Composite_Capability_Index,
            4
        )
        ELSE NULL
    END AS co2_tons_per_capability_point

FROM dbo.fact_ai_models f
LEFT JOIN dbo.dim_hardware hw
    ON f.hardware_id = hw.hardware_id
LEFT JOIN hardware_specs_dedup hws
    ON LOWER(LTRIM(RTRIM(hw.chip_family))) = hws.norm_hw
LEFT JOIN dbo.dim_country_energy p
    ON f.country_id = p.country_id
LEFT JOIN dbo.dim_grid_enriched g
    ON f.grid_id = g.grid_id
LEFT JOIN benchmark_dedup bm
    ON LOWER(LTRIM(RTRIM(f.model_name))) = bm.norm_name;
GO
