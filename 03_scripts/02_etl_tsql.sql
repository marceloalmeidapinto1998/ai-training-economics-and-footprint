USE EpochAI_DW;
GO

-- ============================================================================
-- 1. DIMENSION TABLE: HARDWARE (TDP in Watts and Release Year per Chip)
-- ============================================================================
DROP TABLE IF EXISTS fact_modelos_ia;
DROP TABLE IF EXISTS dim_hardware;
DROP TABLE IF EXISTS dim_pais_energia;
GO

CREATE TABLE dim_hardware (
    hardware_id INT IDENTITY(1,1) PRIMARY KEY,
    chip_family VARCHAR(50) NOT NULL UNIQUE,
    manufacturer VARCHAR(50) NOT NULL,
    release_year INT,
    tdp_watts INT NOT NULL
);

INSERT INTO dim_hardware (chip_family, manufacturer, release_year, tdp_watts) VALUES
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

-- ============================================================================
-- 2. DIMENSION TABLE: COUNTRY & ENERGY (Carbon Intensity & Industrial Tariffs)
-- ============================================================================
CREATE TABLE dim_pais_energia (
    pais_id INT IDENTITY(1,1) PRIMARY KEY,
    country VARCHAR(100) NOT NULL UNIQUE,
    gco2_per_kwh FLOAT NOT NULL,
    industrial_tariff_usd_kwh FLOAT NOT NULL
);

INSERT INTO dim_pais_energia (country, gco2_per_kwh, industrial_tariff_usd_kwh) VALUES
('United States', 369.0, 0.085),
('China', 582.0, 0.088),
('United Kingdom', 207.0, 0.280),
('France', 56.0, 0.190),
('Germany', 381.0, 0.240),
('Canada', 130.0, 0.075),
('Other / Multinational', 400.0, 0.120);
GO

-- ============================================================================
-- 3. FACT TABLE: AI MODELS (Cleaned Metrics, Energy & Cost Calculations)
-- ============================================================================
CREATE TABLE fact_modelos_ia (
    model_id INT IDENTITY(1,1) PRIMARY KEY,
    model_name VARCHAR(255),
    organization VARCHAR(255),
    org_category VARCHAR(100),
    country_raw VARCHAR(255),
    pais_id INT FOREIGN KEY REFERENCES dim_pais_energia(pais_id),
    hardware_id INT FOREIGN KEY REFERENCES dim_hardware(hardware_id),
    publication_date DATE,
    publication_year INT,
    domain VARCHAR(150),
    accessibility VARCHAR(100),
    open_weights VARCHAR(50),
    frontier_model VARCHAR(50),
    parameters FLOAT,
    training_compute_flop FLOAT,
    log10_flop FLOAT,
    hardware_quantity FLOAT,
    training_time_hours FLOAT,
    estimated_power_watts FLOAT,
    total_energy_mwh FLOAT,
    total_cost_usd FLOAT,
    electricity_cost_usd FLOAT,
    estimated_co2_tons FLOAT
);
GO

WITH cte_cleaned_staging AS (
    SELECT 
        LEFT(Model, 255) AS model_name,
        LEFT(Organization, 255) AS organization,
        LEFT(Organization_categorization, 100) AS org_category,
        LEFT(Country_of_organization, 255) AS country_raw,
        
        -- Standardize primary country for energy grid mapping
        CASE 
            WHEN Country_of_organization LIKE '%United States%' THEN 'United States'
            WHEN Country_of_organization LIKE '%China%' THEN 'China'
            WHEN Country_of_organization LIKE '%United Kingdom%' THEN 'United Kingdom'
            WHEN Country_of_organization LIKE '%France%' THEN 'France'
            WHEN Country_of_organization LIKE '%Germany%' THEN 'Germany'
            WHEN Country_of_organization LIKE '%Canada%' THEN 'Canada'
            ELSE 'Other / Multinational'
        END AS standard_country,

        -- Standardize primary GPU/TPU chip family
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
        LEFT(Open_model_weights, 50) AS open_weights,
        LEFT(Frontier_model, 50) AS frontier_model,
        TRY_CAST(Parameters AS FLOAT) AS parameters,
        TRY_CAST(Training_compute_FLOP AS FLOAT) AS flop,
        TRY_CAST(Hardware_quantity AS FLOAT) AS hw_qty,
        TRY_CAST(Training_time_hours AS FLOAT) AS train_hours,
        TRY_CAST(Training_power_draw_W AS FLOAT) AS power_w_raw,
        TRY_CAST(Training_compute_cost_2023_USD AS FLOAT) AS cost_usd
    FROM stg_epoch_models
)
INSERT INTO fact_modelos_ia (
    model_name, organization, org_category, country_raw, pais_id, hardware_id,
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
    p.pais_id,
    h.hardware_id,
    c.pub_date,
    YEAR(c.pub_date) AS publication_year,
    c.domain,
    c.accessibility,
    c.open_weights,
    c.frontier_model,
    c.parameters,
    c.flop,
    CASE WHEN c.flop > 0 THEN LOG10(c.flop) ELSE NULL END AS log10_flop,
    c.hw_qty,
    c.train_hours,
    -- Power draw imputation: use reported Watts or estimate (Chip Count * TDP * 0.85 avg load factor)
    COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) AS estimated_power_watts,
    -- Total Energy in MWh (including standard Hyperscale Data Center PUE = 1.15)
    ((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000000.0) * 1.15 AS total_energy_mwh,
    c.cost_usd,
    -- Pure electricity bill in USD (MWh * 1000 kWh * industrial tariff)
    (((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000.0) * 1.15) * p.industrial_tariff_usd_kwh AS electricity_cost_usd,
    -- Estimated CO2 emissions in metric tons
    ((((COALESCE(c.power_w_raw, c.hw_qty * h.tdp_watts * 0.85) * c.train_hours) / 1000.0) * 1.15) * p.gco2_per_kwh) / 1000000.0 AS estimated_co2_tons
FROM cte_cleaned_staging c
JOIN dim_pais_energia p ON c.standard_country = p.country
JOIN dim_hardware h ON c.standard_chip = h.chip_family;
GO

-- Validation query: Top 15 AI models by energy consumption
SELECT TOP 15 
    model_name, publication_year, 
    ROUND(total_energy_mwh, 1) AS energy_mwh,
    ROUND(total_cost_usd, 0) AS total_cost_usd,
    ROUND(electricity_cost_usd, 0) AS electricity_cost_usd,
    ROUND(estimated_co2_tons, 1) AS co2_tons
FROM fact_modelos_ia
WHERE total_energy_mwh IS NOT NULL
ORDER BY total_energy_mwh DESC;