USE EpochAI_DW;
GO

/* ============================================================================
   DATA QUALITY & GOVERNANCE ASSERTIONS (AUTOMATED WAREHOUSE AUDIT)
   Returns PASS / FAIL status for every critical data engineering rule
   ============================================================================ */

WITH QualityChecks AS (
    -- 1. Referential Integrity: No orphaned hardware foreign keys
    SELECT
        'FK_Integrity_Hardware' AS Test_Name,
        COUNT(*) AS Violation_Count,
        'All hardware_id values in fact_modelos_ia must exist in dim_hardware' AS Rule_Description
    FROM dbo.fact_modelos_ia f
    LEFT JOIN dbo.dim_hardware h ON f.hardware_id = h.hardware_id
    WHERE f.hardware_id IS NOT NULL AND h.hardware_id IS NULL

    UNION ALL

    -- 2. Referential Integrity: No orphaned country/grid foreign keys
    SELECT
        'FK_Integrity_Country_Grid',
        COUNT(*),
        'All pais_id values in fact_modelos_ia must exist in dim_pais_energia'
    FROM dbo.fact_modelos_ia f
    LEFT JOIN dbo.dim_pais_energia p ON f.pais_id = p.pais_id
    WHERE f.pais_id IS NOT NULL AND p.pais_id IS NULL

    UNION ALL

    -- 3. Physical Bounds: Facility PUE must fall within realistic data center range [1.02, 2.50]
    SELECT
        'Physical_Bounds_PUE',
        COUNT(*),
        'Default_Facility_PUE in Dim_Grid_Enriched must be between 1.02 and 2.50'
    FROM dbo.Dim_Grid_Enriched
    WHERE Default_Facility_PUE < 1.02 OR Default_Facility_PUE > 2.50

    UNION ALL

    -- 4. Physical Bounds: Hardware TDP must be positive and below 10,000W
    SELECT
        'Physical_Bounds_Hardware_TDP',
        COUNT(*),
        'TDP_Watts in Dim_Hardware_Specs must be > 0 and <= 10000'
    FROM dbo.Dim_Hardware_Specs
    WHERE TDP_Watts <= 0 OR TDP_Watts > 10000

    UNION ALL

    -- 5. FinOps Logic: Total training cost cannot be negative or less than electricity OpEx
    SELECT
        'FinOps_Cost_Consistency',
        COUNT(*),
        'total_cost_usd must be >= electricity_cost_usd when both are disclosed'
    FROM dbo.fact_modelos_ia
    WHERE total_cost_usd IS NOT NULL
      AND electricity_cost_usd IS NOT NULL
      AND total_cost_usd < electricity_cost_usd

    UNION ALL

    -- 6. Gold Layer Completeness: Ensure view returns active records
    SELECT
        'Gold_View_Non_Empty',
        CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END,
        'vw_models_enriched must return > 0 rows'
    FROM dbo.vw_models_enriched
)
SELECT
    Test_Name,
    CASE WHEN Violation_Count = 0 THEN 'PASS' ELSE 'FAIL' END AS Status,
    Violation_Count,
    Rule_Description
FROM QualityChecks;
GO
