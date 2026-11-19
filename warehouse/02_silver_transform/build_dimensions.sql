USE EpochAI_DW;
GO

/* ============================================================================
   SILVER LAYER: CLEANSING & BUILDING ENRICHED DIMENSION TABLES
   Source: Bronze Staging Tables (dbo.stg_*)
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- 1. DIM_HARDWARE_SPECS (Physical GPU/TPU Telemetry - Epoch AI)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Hardware_Specs', 'U') IS NOT NULL
    DROP TABLE dbo.Dim_Hardware_Specs;
GO

CREATE TABLE dbo.Dim_Hardware_Specs (
    Hardware_Key        INT IDENTITY(1,1) PRIMARY KEY,
    Hardware_Name       NVARCHAR(200) NOT NULL,
    Manufacturer        NVARCHAR(100) NULL,
    Hardware_Type       NVARCHAR(100) NULL,
    Release_Year        INT NULL,
    TDP_Watts           FLOAT NULL,
    Peak_BF16_TFLOPS    FLOAT NULL,
    Peak_FP8_TFLOPS     FLOAT NULL,
    Memory_GB           FLOAT NULL,
    Est_Unit_CapEx_USD  FLOAT NULL,
    Datasheet_URL       NVARCHAR(MAX) NULL,
    Source_Citation     NVARCHAR(250) NOT NULL
);
GO

INSERT INTO dbo.Dim_Hardware_Specs (
    Hardware_Name,
    Manufacturer,
    Hardware_Type,
    Release_Year,
    TDP_Watts,
    Peak_BF16_TFLOPS,
    Peak_FP8_TFLOPS,
    Memory_GB,
    Est_Unit_CapEx_USD,
    Datasheet_URL,
    Source_Citation
)
SELECT
    LTRIM(RTRIM(Hardware_name)) AS Hardware_Name,
    COALESCE(NULLIF(LTRIM(RTRIM(Manufacturer)), ''), 'Unknown') AS Manufacturer,
    COALESCE(NULLIF(LTRIM(RTRIM(Type)), ''), 'Accelerator') AS Hardware_Type,
    YEAR(TRY_CAST(Release_date AS DATE)) AS Release_Year,
    TRY_CAST(TDP_W AS FLOAT) AS TDP_Watts,
    TRY_CAST(Tensor_FP16_BF16_performance_FLOP_s AS FLOAT) / 1e12 AS Peak_BF16_TFLOPS,
    TRY_CAST(FP8_performance_FLOP_s AS FLOAT) / 1e12 AS Peak_FP8_TFLOPS,
    TRY_CAST(Memory_bytes AS FLOAT) / 1073741824.0 AS Memory_GB,
    TRY_CAST(Release_price_USD AS FLOAT) AS Est_Unit_CapEx_USD,
    Link_to_datasheet AS Datasheet_URL,
    'Epoch AI ML Hardware Dataset (epoch.ai)' AS Source_Citation
FROM dbo.stg_epoch_hardware
WHERE Hardware_name IS NOT NULL
  AND TRY_CAST(TDP_W AS FLOAT) > 0;
GO

-- ----------------------------------------------------------------------------
-- 2. DIM_GRID_ENRICHED (Grid Carbon Intensity, Industrial Tariffs & Water WUE)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Grid_Enriched', 'U') IS NOT NULL
    DROP TABLE dbo.Dim_Grid_Enriched;
GO

CREATE TABLE dbo.Dim_Grid_Enriched (
    Grid_Key             INT IDENTITY(1,1) PRIMARY KEY,
    Region_Code          NVARCHAR(20) NOT NULL UNIQUE,
    Country              NVARCHAR(100) NOT NULL,
    Carbon_gCO2_kWh      FLOAT NOT NULL,
    Tariff_USD_MWh       FLOAT NOT NULL,
    WUE_Liters_kWh       FLOAT NOT NULL,
    Default_Facility_PUE FLOAT NOT NULL,
    Source_Citation      NVARCHAR(300) NOT NULL
);
GO

INSERT INTO dbo.Dim_Grid_Enriched (
    Region_Code,
    Country,
    Carbon_gCO2_kWh,
    Tariff_USD_MWh,
    WUE_Liters_kWh,
    Default_Facility_PUE,
    Source_Citation
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
-- 3. DIM_MODEL_BENCHMARKS (Frontier Evaluation & Capability Consolidation)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Model_Benchmarks', 'U') IS NOT NULL
    DROP TABLE dbo.Dim_Model_Benchmarks;
GO

CREATE TABLE dbo.Dim_Model_Benchmarks (
    Benchmark_Key       INT IDENTITY(1,1) PRIMARY KEY,
    Model_Version       NVARCHAR(250) NOT NULL,
    Display_Name        NVARCHAR(250) NULL,
    Model_Group         NVARCHAR(200) NULL,
    Organization        NVARCHAR(200) NULL,
    GPQA_Diamond_Score  FLOAT NULL,
    FrontierMath_Score  FLOAT NULL,
    SWE_Bench_Score     FLOAT NULL,
    MMLU_Score          FLOAT NULL,
    WebDev_Arena_Elo    FLOAT NULL,
    Composite_Index     FLOAT NULL,
    Source_Citation     NVARCHAR(250) NOT NULL
);
GO

WITH BaseModels AS (
    SELECT DISTINCT
        LTRIM(RTRIM(model_version)) AS Model_Version,
        LTRIM(RTRIM(display_name)) AS Display_Name,
        LTRIM(RTRIM(model_group)) AS Model_Group,
        LTRIM(RTRIM(organization)) AS Organization
    FROM dbo.stg_bench_model_metadata
    WHERE model_version IS NOT NULL
),
GPQA AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(mean_score AS FLOAT)) AS score
    FROM dbo.stg_bench_gpqa_diamond GROUP BY LTRIM(RTRIM(Model_version))
),
FMath AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(mean_score AS FLOAT)) AS score
    FROM dbo.stg_bench_frontiermath GROUP BY LTRIM(RTRIM(Model_version))
),
SWE AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(mean_score AS FLOAT)) AS score
    FROM dbo.stg_bench_swe_bench GROUP BY LTRIM(RTRIM(Model_version))
),
MMLU AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(EM AS FLOAT)) AS score
    FROM dbo.stg_bench_mmlu GROUP BY LTRIM(RTRIM(Model_version))
),
Arena AS (
    SELECT LTRIM(RTRIM(Model_version)) AS mv, MAX(TRY_CAST(Arena_Score AS FLOAT)) AS score
    FROM dbo.stg_bench_arena GROUP BY LTRIM(RTRIM(Model_version))
)
INSERT INTO dbo.Dim_Model_Benchmarks (
    Model_Version,
    Display_Name,
    Model_Group,
    Organization,
    GPQA_Diamond_Score,
    FrontierMath_Score,
    SWE_Bench_Score,
    MMLU_Score,
    WebDev_Arena_Elo,
    Composite_Index,
    Source_Citation
)
SELECT
    b.Model_Version,
    b.Display_Name,
    b.Model_Group,
    b.Organization,
    g.score AS GPQA_Diamond_Score,
    f.score AS FrontierMath_Score,
    s.score AS SWE_Bench_Score,
    m.score AS MMLU_Score,
    a.score AS WebDev_Arena_Elo,
    -- Normalized composite capability index (0-100 scale across available benchmarks)
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
    ) AS Composite_Index,
    'Epoch AI Capabilities & Benchmarking Archive (epoch.ai)' AS Source_Citation
FROM BaseModels b
LEFT JOIN GPQA g ON b.Model_Version = g.mv
LEFT JOIN FMath f ON b.Model_Version = f.mv
LEFT JOIN SWE s ON b.Model_Version = s.mv
LEFT JOIN MMLU m ON b.Model_Version = m.mv
LEFT JOIN Arena a ON b.Model_Version = a.mv
WHERE g.score IS NOT NULL
   OR f.score IS NOT NULL
   OR s.score IS NOT NULL
   OR m.score IS NOT NULL
   OR a.score IS NOT NULL;
GO

-- Silver Layer Row Count Verification
SELECT 'Dim_Hardware_Specs' AS Table_Name, COUNT(*) AS Row_Count FROM dbo.Dim_Hardware_Specs
UNION ALL
SELECT 'Dim_Grid_Enriched', COUNT(*) FROM dbo.Dim_Grid_Enriched
UNION ALL
SELECT 'Dim_Model_Benchmarks', COUNT(*) FROM dbo.Dim_Model_Benchmarks;
GO
