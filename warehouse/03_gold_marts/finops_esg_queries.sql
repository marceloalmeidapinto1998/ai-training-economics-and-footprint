USE EpochAI_DW;
GO

-- ============================================================================
-- SECTION 1: DATA COMPLETENESS & THE AI TRANSPARENCY GAP (2018 - 2026)
-- Business Question: How has model scale evolved, and how has the public
--                    disclosure of energy and cost metrics shifted over time?
-- ============================================================================
WITH yearly_disclosure AS (
    SELECT
        publication_year,
        COUNT(*) AS total_models,
        COUNT(training_compute_flop) AS disclosed_compute_models,
        COUNT(facility_total_energy_mwh) AS disclosed_energy_models,
        COUNT(total_cost_usd) AS disclosed_cost_models,
        ROUND(AVG(log10_flop), 2) AS avg_log10_flop,
        ROUND(MAX(log10_flop), 2) AS peak_log10_flop
    FROM dbo.vw_models_enriched
    WHERE publication_year BETWEEN 2018 AND 2026
    GROUP BY publication_year
)
SELECT
    publication_year,
    total_models,
    disclosed_energy_models,
    CAST(ROUND(100.0 * disclosed_energy_models / NULLIF(total_models, 0), 2) AS DECIMAL(5, 2)) AS energy_disclosure_pct,
    disclosed_cost_models,
    CAST(ROUND(100.0 * disclosed_cost_models / NULLIF(total_models, 0), 2) AS DECIMAL(5, 2)) AS cost_disclosure_pct,
    avg_log10_flop,
    peak_log10_flop
FROM yearly_disclosure
ORDER BY publication_year ASC;
GO

-- ============================================================================
-- SECTION 2: FINOPS — TRAINING BUDGET BREAKDOWN (CAPEX VS. OPEX)
-- Business Question: Across the highest-budget AI training runs, what share
--                    goes to hardware CapEx vs. facility electricity OpEx?
-- ============================================================================
SELECT TOP 15
    model_name,
    organization,
    publication_year,
    chip_family,
    primary_country,
    ROUND(total_cost_usd / 1e6, 2) AS total_cost_musd,
    ROUND(hardware_infra_cost_usd / 1e6, 2) AS hardware_capex_musd,
    ROUND(facility_electricity_cost_usd / 1e6, 2) AS facility_opex_musd,
    ROUND(100.0 * hardware_infra_cost_usd / NULLIF(total_cost_usd, 0), 1) AS capex_share_pct,
    ROUND(100.0 * facility_electricity_cost_usd / NULLIF(total_cost_usd, 0), 1) AS opex_share_pct
FROM dbo.vw_models_enriched
WHERE total_cost_usd IS NOT NULL
  AND hardware_infra_cost_usd IS NOT NULL
ORDER BY total_cost_usd DESC;
GO


-- ============================================================================
-- SECTION 3: ESG & HARDWARE EFFICIENCY — SCALE VS. ENERGY INTENSITY
-- Business Question: Which accelerator families consume the most aggregate
--                    energy vs. which deliver the lowest energy per 10^24 FLOP?
-- ============================================================================
SELECT
    chip_family,
    chip_manufacturer,
    COUNT(*) AS model_count,
    ROUND(AVG(tdp_watts), 0) AS avg_tdp_watts,
    ROUND(SUM(facility_total_energy_mwh), 1) AS cumulative_facility_mwh,
    ROUND(AVG(facility_total_energy_mwh), 1) AS mean_facility_mwh,
    ROUND(AVG(water_footprint_megaliters), 2) AS mean_water_megaliters,
    ROUND(
        AVG(
            CASE
                WHEN training_compute_flop > 0 AND facility_total_energy_mwh > 0
                THEN facility_total_energy_mwh / (training_compute_flop / 1e24)
                ELSE NULL
            END
        ), 3
    ) AS avg_mwh_per_1e24_flop
FROM dbo.vw_models_enriched
WHERE facility_total_energy_mwh IS NOT NULL
  AND chip_family <> 'Other / Unspecified'
GROUP BY chip_family, chip_manufacturer
HAVING COUNT(*) >= 2
ORDER BY cumulative_facility_mwh DESC;
GO


-- ============================================================================
-- SECTION 4: ESG — TOP ENVIRONMENTAL FOOTPRINT LEADERS (ENERGY, WATER, CO2)
-- Business Question: What is the full facility-adjusted footprint (MWh, water
--                    cooling Megaliters, CO2 tons, and US household equivalents)
--                    of the most energy-intensive models?
-- ============================================================================
SELECT TOP 15
    model_name,
    organization,
    publication_year,
    primary_country,
    grid_region_code,
    facility_pue,
    wue_liters_kwh,
    ROUND(it_energy_mwh, 1) AS it_energy_mwh,
    ROUND(facility_total_energy_mwh, 1) AS facility_total_energy_mwh,
    eq_us_households_year,
    ROUND(pue_adjusted_co2_tons, 1) AS pue_adjusted_co2_tons,
    ROUND(water_footprint_megaliters, 2) AS water_footprint_megaliters
FROM dbo.vw_models_enriched
WHERE facility_total_energy_mwh IS NOT NULL
ORDER BY facility_total_energy_mwh DESC;
GO


-- ============================================================================
-- SECTION 5: GEOPOLITICAL SITE SELECTION — 50,000 MWH WORKLOAD SIMULATION
-- Business Question: If we train a standardized 50,000 MWh frontier model across
--                    each regional grid, how do electricity cost, CO2 emissions,
--                    and cooling water consumption compare?
-- ============================================================================
WITH workload_baseline AS (
    SELECT 50000.0 AS it_workload_mwh
)
SELECT
    g.region_code,
    g.country,
    g.default_facility_pue,
    g.carbon_gco2_kwh,
    g.tariff_usd_mwh,
    g.wue_liters_kwh,
    ROUND(w.it_workload_mwh * g.default_facility_pue, 0) AS facility_energy_mwh,
    ROUND((w.it_workload_mwh * g.default_facility_pue * g.tariff_usd_mwh) / 1e6, 2) AS electricity_bill_musd,
    ROUND((w.it_workload_mwh * g.default_facility_pue * 1000.0 * g.carbon_gco2_kwh) / 1e6, 0) AS co2_emissions_tons,
    ROUND((w.it_workload_mwh * g.default_facility_pue * 1000.0 * g.wue_liters_kwh) / 1e6, 2) AS cooling_water_megaliters
FROM dbo.dim_grid_enriched g
CROSS JOIN workload_baseline w
ORDER BY co2_emissions_tons ASC;
GO


-- ============================================================================
-- SECTION 6: FRONTIER LAB BENCHMARKING & CAPABILITY ROI (PARETO LEADERS)
-- Business Question: Which frontier models deliver the highest benchmark
--                    capability per million USD spent and per ton of CO2?
-- ============================================================================
SELECT TOP 20
    DENSE_RANK() OVER (ORDER BY Composite_Capability_Index DESC) AS capability_rank,
    model_name,
    organization,
    publication_year,
    ROUND(Composite_Capability_Index, 2) AS composite_capability_index,
    ROUND(GPQA_Diamond_Score * 100.0, 1) AS gpqa_pct,
    ROUND(FrontierMath_Score * 100.0, 1) AS frontiermath_pct,
    ROUND(SWE_Bench_Score * 100.0, 1) AS swe_bench_pct,
    ROUND(total_cost_usd / 1e6, 2) AS total_cost_musd,
    usd_per_capability_point,
    co2_tons_per_capability_point
FROM dbo.vw_models_enriched
WHERE Composite_Capability_Index IS NOT NULL
ORDER BY Composite_Capability_Index DESC;
GO


-- ============================================================================
-- SECTION 7: GOVERNANCE & OPEN-WEIGHTS VS. CLOSED COMMERCIAL APIs
-- Business Question: How does model accessibility (open weights vs. closed API)
--                    correlate with compute scale and environmental transparency?
-- ============================================================================
SELECT
    COALESCE(NULLIF(LTRIM(RTRIM(open_weights)), ''), 'Unknown / Unspecified') AS open_weights_status,
    COUNT(*) AS total_models,
    ROUND(AVG(log10_flop), 2) AS avg_log10_flop,
    COUNT(facility_total_energy_mwh) AS models_with_energy_data,
    ROUND(100.0 * COUNT(facility_total_energy_mwh) / NULLIF(COUNT(*), 0), 1) AS energy_transparency_pct,
    ROUND(AVG(facility_total_energy_mwh), 1) AS avg_facility_energy_mwh,
    ROUND(AVG(Composite_Capability_Index), 2) AS avg_capability_index
FROM dbo.vw_models_enriched
WHERE publication_year >= 2022
GROUP BY COALESCE(NULLIF(LTRIM(RTRIM(open_weights)), ''), 'Unknown / Unspecified')
ORDER BY total_models DESC;
GO