USE EpochAI_DW;
GO

/* ============================================================================
   DATA QUALITY & GOVERNANCE ASSERTIONS (AUTOMATED WAREHOUSE AUDIT)
   Standard: English lowercase snake_case
   ============================================================================ */

WITH quality_checks AS (
    SELECT
        'fk_integrity_hardware' AS test_name,
        COUNT(*) AS violation_count,
        'All hardware_id values in fact_ai_models must exist in dim_hardware' AS rule_description
    FROM dbo.fact_ai_models f
    LEFT JOIN dbo.dim_hardware h ON f.hardware_id = h.hardware_id
    WHERE f.hardware_id IS NOT NULL AND h.hardware_id IS NULL

    UNION ALL

    SELECT
        'fk_integrity_country_energy',
        COUNT(*),
        'All country_id values in fact_ai_models must exist in dim_country_energy'
    FROM dbo.fact_ai_models f
    LEFT JOIN dbo.dim_country_energy p ON f.country_id = p.country_id
    WHERE f.country_id IS NOT NULL AND p.country_id IS NULL

    UNION ALL

    SELECT
        'physical_bounds_pue',
        COUNT(*),
        'default_facility_pue in dim_grid_enriched must be between 1.02 and 2.50'
    FROM dbo.dim_grid_enriched
    WHERE default_facility_pue < 1.02 OR default_facility_pue > 2.50

    UNION ALL

    SELECT
        'physical_bounds_hardware_tdp',
        COUNT(*),
        'tdp_watts in dim_hardware_specs must be > 0 and <= 10000'
    FROM dbo.dim_hardware_specs
    WHERE tdp_watts <= 0 OR tdp_watts > 10000

    UNION ALL

    SELECT
        'finops_cost_consistency',
        COUNT(*),
        'total_cost_usd must be >= electricity_cost_usd when both are disclosed'
    FROM dbo.fact_ai_models
    WHERE total_cost_usd IS NOT NULL
      AND electricity_cost_usd IS NOT NULL
      AND total_cost_usd < electricity_cost_usd

    UNION ALL

    SELECT
        'gold_view_non_empty',
        CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END,
        'vw_models_enriched must return > 0 rows'
    FROM dbo.vw_models_enriched
)
SELECT
    test_name,
    CASE WHEN violation_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
    violation_count,
    rule_description
FROM quality_checks;
GO
