USE EpochAI_DW;
GO

/* ============================================================================
   SILVER LAYER: CORE STAR SCHEMA (FACT & BASE DIMENSIONS)
   Standard: English lowercase snake_case with full Foreign Key integrity
   ============================================================================ */

DROP TABLE IF EXISTS dbo.fact_ai_models;
DROP TABLE IF EXISTS dbo.fact_modelos_ia;
DROP TABLE IF EXISTS dbo.dim_hardware;
DROP TABLE IF EXISTS dbo.dim_country_energy;
DROP TABLE IF EXISTS dbo.dim_pais_energia;
GO

-- 1. dim_hardware (Base chip family taxonomy)
CREATE TABLE dbo.dim_hardware (
    hardware_id   INT IDENTITY(1,1) PRIMARY KEY,
    chip_family   VARCHAR(50) NOT NULL UNIQUE,
    manufacturer  VARCHAR(50) NOT NULL,
    release_year  INT NULL,
    tdp_watts     INT NOT NULL
);

INSERT INTO dbo.dim_hardware (chip_family, manufacturer, release_year, tdp_watts) VALUES
('NVIDIA V100', 'NVIDIA', 2017, 300),
('NVIDIA A100', 'NVIDIA', 2020, 400),
('NVIDIA H100', 'NVIDIA', 2022, 700),
('NVIDIA H200', 'NVIDIA', 2024, 700),
('NVIDIA B200', 'NVIDIA', 2024, 1000),
('Google TPU v3', 'Google', 2018, 280),
('Google TPU v4', 'Google', 2021, 275),
('Google TPU v5e', 'Google', 2023, 200),
('Google TPU v5p', 'Google', 2023, 450),
('Other / Unspecified', 'Various', NULL, 350);
GO

-- 2. dim_country_energy (Base national carbon intensity & industrial tariffs)
CREATE TABLE dbo.dim_country_energy (
    country_id                 INT IDENTITY(1,1) PRIMARY KEY,
    country                    VARCHAR(100) NOT NULL UNIQUE,
    gco2_per_kwh               FLOAT NOT NULL,
    industrial_tariff_usd_kwh  FLOAT NOT NULL
);

INSERT INTO dbo.dim_country_energy (country, gco2_per_kwh, industrial_tariff_usd_kwh) VALUES
('United States', 369.0, 0.085),
('China', 582.0, 0.088),
('United Kingdom', 207.0, 0.280),
('France', 56.0, 0.190),
('Germany', 381.0, 0.240),
('Canada', 130.0, 0.075),
('Other / Multinational', 400.0, 0.120);
GO

-- 3. fact_ai_models (Central Fact Table with all 5 Star Schema Foreign Keys)
CREATE TABLE dbo.fact_ai_models (
    model_id               INT IDENTITY(1,1) PRIMARY KEY,
    model_name             VARCHAR(255) NOT NULL,
    organization           VARCHAR(255) NULL,
    org_category           VARCHAR(100) NULL,
    country_raw            VARCHAR(255) NULL,
    country_id             INT NULL CONSTRAINT fk_fact_country_energy FOREIGN KEY REFERENCES dbo.dim_country_energy(country_id),
    hardware_id            INT NULL CONSTRAINT fk_fact_hardware FOREIGN KEY REFERENCES dbo.dim_hardware(hardware_id),
    hardware_spec_id       INT NULL CONSTRAINT fk_fact_hardware_specs FOREIGN KEY REFERENCES dbo.dim_hardware_specs(hardware_spec_id),
    grid_id                INT NULL CONSTRAINT fk_fact_grid_enriched FOREIGN KEY REFERENCES dbo.dim_grid_enriched(grid_id),
    benchmark_id           INT NULL CONSTRAINT fk_fact_model_benchmarks FOREIGN KEY REFERENCES dbo.dim_model_benchmarks(benchmark_id),
    publication_date       DATE NULL,
    publication_year       INT NULL,
    domain                 VARCHAR(150) NULL,
    accessibility          VARCHAR(100) NULL,
    open_weights           VARCHAR(50) NULL,
    frontier_model         VARCHAR(50) NULL,
    parameters             FLOAT NULL,
    training_compute_flop  FLOAT NULL,
    log10_flop             FLOAT NULL,
    hardware_quantity      FLOAT NULL,
    training_time_hours    FLOAT NULL,
    estimated_power_watts  FLOAT NULL,
    total_energy_mwh       FLOAT NULL,
    total_cost_usd         FLOAT NULL,
    electricity_cost_usd   FLOAT NULL,
    estimated_co2_tons     FLOAT NULL
);
GO

WITH cte_cleaned_staging AS (
    SELECT 
        LEFT(Model, 255) AS model_name,
        LEFT(Organization, 255) AS organization,
        LEFT(Organization_categorization, 100) AS org_category,
        LEFT(Country_of_organization, 255) AS country_raw,
        CASE 
            WHEN Country_of_organization LIKE '%United States%' THEN 'United States'
            WHEN Country_of_organization LIKE '%China%' THEN 'China'
            WHEN Country_of_organization LIKE '%United Kingdom%' THEN 'United Kingdom'
            WHEN Country_of_organization LIKE '%France%' THEN 'France'
            WHEN Country_of_organization LIKE '%Germany%' THEN 'Germany'
            WHEN Country_of_organization LIKE '%Canada%' THEN 'Canada'
            ELSE 'Other / Multinational'
        END AS standard_country,
        CASE 
            WHEN Country_of_organization LIKE '%United States%' THEN 'US-VA'
            WHEN Country_of_organization LIKE '%China%' THEN 'CN-EAST'
            WHEN Country_of_organization LIKE '%United Kingdom%' THEN 'UK-LON'
            WHEN Country_of_organization LIKE '%Germany%' THEN 'EU-DE'
            WHEN Country_of_organization LIKE '%Sweden%' THEN 'SE-NORD'
            WHEN Country_of_organization LIKE '%Canada%' THEN 'CA-QC'
            ELSE NULL
        END AS standard_region_code,
        CASE 
            WHEN Training_hardware LIKE '%B200%' THEN 'NVIDIA B200'
            WHEN Training_hardware LIKE '%H200%' THEN 'NVIDIA H200'
            WHEN Training_hardware LIKE '%H100%' THEN 'NVIDIA H100'
            WHEN Training_hardware LIKE '%A100%' THEN 'NVIDIA A100'
            WHEN Training_hardware LIKE '%V100%' THEN 'NVIDIA V100'
            WHEN Training_hardware LIKE '%TPU v5p%' THEN 'Google TPU v5p'
            WHEN Training_hardware LIKE '%TPU v5e%' THEN 'Google TPU v5e'
            WHEN Training_hardware LIKE '%TPU v4%' THEN 'Google TPU v4'
            WHEN Training_hardware LIKE '%TPU v3%' THEN 'Google TPU v3'
            ELSE 'Other / Unspecified'
        END AS standard_chip,
        TRY_CAST(Publication_date AS DATE) AS pub_date,
        LEFT(Domain, 150) AS domain,
        LEFT(Model_accessibility, 100) AS accessibility,
        LEFT([Open_model_weights?], 50) AS open_weights,
        LEFT(Frontier_model, 50) AS frontier_model,
        TRY_CAST(Parameters AS FLOAT) AS parameters,
        TRY_CAST(Training_compute_FLOP AS FLOAT) AS flop,
        TRY_CAST(Hardware_quantity AS FLOAT) AS hw_qty,
        TRY_CAST(Training_time_hours AS FLOAT) AS train_hours,
        TRY_CAST(Training_power_draw_W AS FLOAT) AS power_w_raw,
        TRY_CAST(Training_compute_cost_2023_USD AS FLOAT) AS cost_usd
    FROM dbo.stg_epoch_models
),
hw_spec_lookup AS (
    SELECT LOWER(LTRIM(RTRIM(hardware_name))) AS norm_hw, MIN(hardware_spec_id) AS hardware_spec_id
    FROM dbo.dim_hardware_specs
    GROUP BY LOWER(LTRIM(RTRIM(hardware_name)))
),
bench_lookup AS (
    SELECT LOWER(LTRIM(RTRIM(COALESCE(display_name, model_group, model_version)))) AS norm_name, MIN(benchmark_id) AS benchmark_id
    FROM dbo.dim_model_benchmarks
    GROUP BY LOWER(LTRIM(RTRIM(COALESCE(display_name, model_group, model_version))))
)
INSERT INTO dbo.fact_ai_models (
    model_name, organization, org_category, country_raw,
    country_id, hardware_id, hardware_spec_id, grid_id, benchmark_id,
    publication_date, publication_year, domain, accessibility, open_weights, frontier_model,
    parameters, training_compute_flop, log10_flop,
    hardware_quantity, training_time_hours, estimated_power_watts,
    total_energy_mwh, total_cost_usd, electricity_cost_usd, estimated_co2_tons
)
SELECT 
    c.model_name,
    c.organization,
    c.org_category,
    c.country_raw,
    p.country_id,
    h.hardware_id,
    hs.hardware_spec_id,
    g.grid_id,
    bm.benchmark_id,
    c.pub_date,
    YEAR(c.pub_date),
    c.domain,
    c.accessibility,
    c.open_weights,
    c.frontier_model,
    c.parameters,
    c.flop,
    CASE WHEN c.flop > 0 THEN LOG10(c.flop) ELSE NULL END,
    c.hw_qty,
    c.train_hours,
    COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85),
    ((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000000.0) * 1.15,
    CASE WHEN c.cost_usd IS NOT NULL AND ((((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000.0) * 1.15) * p.industrial_tariff_usd_kwh) > c.cost_usd THEN CEILING(((((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000.0) * 1.15) * p.industrial_tariff_usd_kwh) * 100.0) / 100.0 ELSE c.cost_usd END,
    (((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000.0) * 1.15) * p.industrial_tariff_usd_kwh,
    ((((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000.0) * 1.15) * p.gco2_per_kwh) / 1000000.0
FROM cte_cleaned_staging c
JOIN dbo.dim_country_energy p ON c.standard_country = p.country
JOIN dbo.dim_hardware h ON c.standard_chip = h.chip_family
LEFT JOIN hw_spec_lookup hs ON LOWER(LTRIM(RTRIM(c.standard_chip))) = hs.norm_hw
LEFT JOIN dbo.dim_grid_enriched g ON c.standard_region_code = g.region_code
LEFT JOIN bench_lookup bm ON LOWER(LTRIM(RTRIM(c.model_name))) = bm.norm_name;
GO
