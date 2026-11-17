-- ============================================================================
-- SCRIPT: 03_views_analise_models.sql
-- DATABASE: EpochAI_DW
-- DESCRIPTION: Semantic analytical layer providing denormalized Star Schema
--              views and pre-aggregated temporal scaling views for Python
--              (VS Code / Plotly) and BI consumption.
-- ============================================================================

USE EpochAI_DW;
GO

-- ============================================================================
-- VIEW 1: MASTER ANALYTICAL VIEW (Denormalized Star Schema for Python EDA)
-- ============================================================================
CREATE OR ALTER VIEW vw_ai_models_master AS
SELECT 
    f.model_id,
    f.model_name,
    f.organization,
    f.org_category,
    p.country AS primary_country,
    p.gco2_per_kwh,
    p.industrial_tariff_usd_kwh,
    h.chip_family,
    h.manufacturer AS chip_manufacturer,
    h.release_year AS chip_release_year,
    h.tdp_watts,
    f.publication_date,
    f.publication_year,
    f.domain,
    f.accessibility,
    f.open_weights,
    f.frontier_model,
    f.parameters,
    f.training_compute_flop,
    f.log10_flop,
    f.hardware_quantity,
    f.training_time_hours,
    ROUND(f.training_time_hours / 24.0, 1) AS training_days,
    f.estimated_power_watts,
    f.total_energy_mwh,
    -- Equivalent European households powered for 1 year (avg 3.5 MWh/year)
    ROUND(f.total_energy_mwh / 3.5, 1) AS eq_households_year,
    f.total_cost_usd,
    f.electricity_cost_usd,
    -- Hardware & Cloud infrastructure cost share (Total Cost - Electricity Cost)
    CASE 
        WHEN f.total_cost_usd IS NOT NULL AND f.electricity_cost_usd IS NOT NULL 
             AND f.total_cost_usd > f.electricity_cost_usd
        THEN ROUND(f.total_cost_usd - f.electricity_cost_usd, 2)
        ELSE NULL 
    END AS hardware_infra_cost_usd,
    -- Electricity share of total budget (%)
    CASE 
        WHEN f.total_cost_usd > 0 AND f.electricity_cost_usd IS NOT NULL 
             AND f.total_cost_usd > f.electricity_cost_usd
        THEN ROUND((f.electricity_cost_usd / f.total_cost_usd) * 100.0, 2)
        ELSE NULL 
    END AS electricity_share_pct,
    f.estimated_co2_tons
FROM fact_modelos_ia f
INNER JOIN dim_pais_energia p ON f.pais_id = p.pais_id
INNER JOIN dim_hardware h ON f.hardware_id = h.hardware_id;
GO

-- ============================================================================
-- VIEW 2: ANNUAL TRENDS & SCALING LAWS (2015 - 2026)
-- ============================================================================
CREATE OR ALTER VIEW vw_annual_energy_trends AS
SELECT 
    publication_year,
    COUNT(*) AS total_models,
    COUNT(total_energy_mwh) AS models_with_energy_data,
    ROUND(AVG(log10_flop), 2) AS avg_log10_flop,
    MAX(training_compute_flop) AS max_compute_flop,
    ROUND(SUM(total_energy_mwh), 1) AS total_energy_mwh_year,
    ROUND(AVG(total_energy_mwh), 1) AS avg_energy_mwh_per_model,
    ROUND(AVG(total_cost_usd), 0) AS avg_training_cost_usd,
    ROUND(SUM(estimated_co2_tons), 1) AS total_co2_tons_year
FROM vw_ai_models_master
WHERE publication_year >= 2015
GROUP BY publication_year;
GO