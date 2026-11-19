USE EpochAI_DW;
GO

/* ============================================================================
   SILVER LAYER: CLEANSING & BUILDING ENRICHED DIMENSION TABLES
   Source: Bronze Staging Tables (dbo.stg_*)
   Standard: English lowercase snake_case
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- 1. dim_hardware_specs (Physical GPU/TPU Telemetry - Epoch AI)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fact_ai_models', 'U') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.fk_fact_hardware_specs', 'F') IS NOT NULL
        ALTER TABLE dbo.fact_ai_models DROP CONSTRAINT fk_fact_hardware_specs;
    IF OBJECT_ID('dbo.fk_fact_grid_enriched', 'F') IS NOT NULL
        ALTER TABLE dbo.fact_ai_models DROP CONSTRAINT fk_fact_grid_enriched;
    IF OBJECT_ID('dbo.fk_fact_model_benchmarks', 'F') IS NOT NULL
        ALTER TABLE dbo.fact_ai_models DROP CONSTRAINT fk_fact_model_benchmarks;
END
GO

DROP TABLE IF EXISTS dbo.dim_hardware_specs;
DROP TABLE IF EXISTS dbo.Dim_Hardware_Specs;
GO

CREATE TABLE dbo.dim_hardware_specs (
    hardware_spec_id    INT IDENTITY(1,1) PRIMARY KEY,
    hardware_name       NVARCHAR(200) NOT NULL,
    manufacturer        NVARCHAR(100) NULL,
    hardware_type       NVARCHAR(100) NULL,
    release_year        INT NULL,
    tdp_watts           FLOAT NULL,
    peak_bf16_tflops    FLOAT NULL,
    peak_fp8_tflops     FLOAT NULL,
    memory_gb           FLOAT NULL,
    est_unit_capex_usd  FLOAT NULL,
    datasheet_url       NVARCHAR(MAX) NULL,
    source_citation     NVARCHAR(250) NOT NULL
);
GO

INSERT INTO dbo.dim_hardware_specs (
    hardware_name, manufacturer, hardware_type, release_year, tdp_watts,
    peak_bf16_tflops, peak_fp8_tflops, memory_gb, est_unit_capex_usd,
    datasheet_url, source_citation
)
SELECT
    LTRIM(RTRIM(Hardware_name)),
    COALESCE(NULLIF(LTRIM(RTRIM(Manufacturer)), ''), 'Unknown'),
    COALESCE(NULLIF(LTRIM(RTRIM(Type)), ''), 'Accelerator'),
    YEAR(TRY_CAST(Release_date AS DATE)),
    TRY_CAST(TDP_W AS FLOAT),
    TRY_CAST(Tensor_FP16_BF16_performance_FLOP_s AS FLOAT) / 1e12,
    TRY_CAST(FP8_performance_FLOP_s AS FLOAT) / 1e12,
    TRY_CAST(Memory_bytes AS FLOAT) / 1073741824.0,
    TRY_CAST(Release_price_USD AS FLOAT),
    Link_to_datasheet,
    'Epoch AI ML Hardware Dataset (epoch.ai)'
FROM dbo.stg_epoch_hardware
WHERE Hardware_name IS NOT NULL
  AND TRY_CAST(TDP_W AS FLOAT) > 0;
GO

-- ----------------------------------------------------------------------------
-- 2. dim_grid_enriched (Grid Carbon Intensity, Industrial Tariffs & Water WUE)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.dim_grid_enriched;
DROP TABLE IF EXISTS dbo.Dim_Grid_Enriched;
GO

CREATE TABLE dbo.dim_grid_enriched (
    grid_id              INT IDENTITY(1,1) PRIMARY KEY,
    region_code          NVARCHAR(20) NOT NULL UNIQUE,
    country              NVARCHAR(100) NOT NULL,
    carbon_gco2_kwh      FLOAT NOT NULL,
    tariff_usd_mwh       FLOAT NOT NULL,
    wue_liters_kwh       FLOAT NOT NULL,
    default_facility_pue FLOAT NOT NULL,
    source_citation      NVARCHAR(300) NOT NULL
);
GO

INSERT INTO dbo.dim_grid_enriched (
    region_code, country, carbon_gco2_kwh, tariff_usd_mwh,
    wue_liters_kwh, default_facility_pue, source_citation
)
SELECT
    LTRIM(RTRIM(Region_Code)),
    LTRIM(RTRIM(Country)),
    TRY_CAST(Carbon_gCO2_kWh AS FLOAT),
    TRY_CAST(Tariff_USD_MWh AS FLOAT),
    TRY_CAST(WUE_Liters_kWh AS FLOAT),
    TRY_CAST(Default_Facility_PUE AS FLOAT),
    Source_Citation
FROM dbo.stg_grid_intensity_wue;
GO

-- ----------------------------------------------------------------------------
-- 3. dim_model_benchmarks (Frontier Evaluation & Capability Consolidation)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.dim_model_benchmarks;
DROP TABLE IF EXISTS dbo.Dim_Model_Benchmarks;
GO

CREATE TABLE dbo.dim_model_benchmarks (
    benchmark_id        INT IDENTITY(1,1) PRIMARY KEY,
    model_version       NVARCHAR(250) NOT NULL,
    display_name        NVARCHAR(250) NULL,
    model_group         NVARCHAR(200) NULL,
    organization        NVARCHAR(200) NULL,
    gpqa_diamond_score  FLOAT NULL,
    frontiermath_score  FLOAT NULL,
    swe_bench_score     FLOAT NULL,
    mmlu_score          FLOAT NULL,
    webdev_arena_elo    FLOAT NULL,
    composite_index     FLOAT NULL,
    source_citation     NVARCHAR(250) NOT NULL
);
GO

WITH base_models AS (
    SELECT DISTINCT
        LTRIM(RTRIM(model_version)) AS model_version,
        LTRIM(RTRIM(display_name)) AS display_name,
        LTRIM(RTRIM(model_group)) AS model_group,
        LTRIM(RTRIM(organization)) AS organization
    FROM dbo.stg_bench_model_metadata
    WHERE model_version IS NOT NULL
),
gpqa AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(mean_score AS FLOAT)) AS score
    FROM dbo.stg_bench_gpqa_diamond GROUP BY LTRIM(RTRIM(Model_version))
),
fmath AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(mean_score AS FLOAT)) AS score
    FROM dbo.stg_bench_frontiermath GROUP BY LTRIM(RTRIM(Model_version))
),
swe AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(mean_score AS FLOAT)) AS score
    FROM dbo.stg_bench_swe_bench GROUP BY LTRIM(RTRIM(Model_version))
),
mmlu AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(EM AS FLOAT)) AS score
    FROM dbo.stg_bench_mmlu GROUP BY LTRIM(RTRIM(Model_version))
),
arena AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(Arena_Score AS FLOAT)) AS score
    FROM dbo.stg_bench_arena GROUP BY LTRIM(RTRIM(Model_version))
)
INSERT INTO dbo.dim_model_benchmarks (
    model_version, display_name, model_group, organization,
    gpqa_diamond_score, frontiermath_score, swe_bench_score,
    mmlu_score, webdev_arena_elo, composite_index, source_citation
)
SELECT
    b.model_version,
    b.display_name,
    b.model_group,
    b.organization,
    g.score,
    f.score,
    s.score,
    m.score,
    a.score,
    (
        COALESCE(g.score * 100.0, 0) +
        COALESCE(f.score * 100.0, 0) +
        COALESCE(s.score * 100.0, 0) +
        COALESCE(m.score * 100.0, 0)
    ) / NULLIF(
        (CASE WHEN g.score IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN f.score IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN s.score IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN m.score IS NOT NULL THEN 1 ELSE 0 END), 0
    ),
    'Epoch AI Capabilities & Benchmarking Archive (epoch.ai)'
FROM base_models b
LEFT JOIN gpqa g ON b.model_version = g.mv
LEFT JOIN fmath f ON b.model_version = f.mv
LEFT JOIN swe s ON b.model_version = s.mv
LEFT JOIN mmlu m ON b.model_version = m.mv
LEFT JOIN arena a ON b.model_version = a.mv
WHERE g.score IS NOT NULL
   OR f.score IS NOT NULL
   OR s.score IS NOT NULL
   OR m.score IS NOT NULL
   OR a.score IS NOT NULL;
GO

SELECT 'dim_hardware_specs' AS table_name, COUNT(*) AS row_count FROM dbo.dim_hardware_specs
UNION ALL
SELECT 'dim_grid_enriched', COUNT(*) FROM dbo.dim_grid_enriched
UNION ALL
SELECT 'dim_model_benchmarks', COUNT(*) FROM dbo.dim_model_benchmarks;
GO
