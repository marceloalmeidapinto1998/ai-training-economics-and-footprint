-- ============================================================================
-- SCRIPT: 04_eda_queries_tsql.sql
-- DATABASE: EpochAI_DW
-- DESCRIPTION: Progressive Exploratory Data Analysis (EDA) querying the Star
--              Schema (dim_hardware, dim_pais_energia, fact_modelos_ia) from
--              reference audits and univariate statistics to multi-dimensional
--              joins, CTEs, and Window Functions.
-- ============================================================================

USE EpochAI_DW;
GO


-- ============================================================================
-- STAGE 1: DIMENSION EXPLORATION (Reference Data Validation)
-- ============================================================================

-- 1A. Inspect Hardware Dimension ordered by Thermal Design Power (TDP Watts)
-- Purpose: Validate reference data integrity and observe generational increases in chip power draw.
SELECT 
    hardware_id,
    chip_family,
    manufacturer,
    release_year,
    tdp_watts
FROM dim_hardware
ORDER BY tdp_watts DESC;
GO

/* 
KEY INSIGHT (Stage 1A - Hardware Thermal Evolution):
- Ordering by TDP reveals a clear physical trend: between 2017 (NVIDIA V100 at 300W) and 2024 (NVIDIA B200 at 1,000W), individual chip power demand more than tripled (+233%).
- Google TPUs show a more conservative thermal profile (200W–450W), relying on larger interconnected pods rather than extreme per-chip wattage.
- Total energy demand scales rapidly because two factors rise simultaneously: the number of chips inside AI clusters and the power draw (TDP) of each individual chip.
*/

-- 1B. Inspect Country & Energy Grid Dimension ordered by Carbon Intensity
-- Purpose: Compare grid carbon intensity (gCO2/kWh) and industrial electricity tariffs across AI hubs.
SELECT 
    pais_id,
    country,
    gco2_per_kwh,
    industrial_tariff_usd_kwh
FROM dim_pais_energia
ORDER BY gco2_per_kwh DESC;
GO

/* 
KEY INSIGHT (Stage 1B - Geopolitical Grid Carbon & Cost Trade-offs):
- 10x Carbon Intensity Gap: China (582 gCO2/kWh) has over 10 times the carbon intensity of France (56 gCO2/kWh), meaning an identical AI training run emits ~10.4x more CO2 in China than in France.
- The European Cost Penalty: Major European hubs face industrial electricity tariffs 2x to 3x higher than North America and China (UK $0.28/kWh, Germany $0.24/kWh, France $0.19/kWh vs. Canada $0.075/kWh, US $0.085/kWh, China $0.088/kWh).
- Strategic Outliers: Canada offers the rare "sweet spot" of ultra-low industrial electricity cost ($0.075/kWh) paired with a clean hydro-dominated grid (130 gCO2/kWh), whereas the US and China combine cheap power with moderate-to-high fossil grid intensity (369–582 gCO2/kWh).
*/


-- ============================================================================
-- STAGE 2: FACT TABLE AUDIT & UNIVARIATE DESCRIPTIVE STATISTICS
-- ============================================================================

-- 2A. Row counts, timeline boundaries, and missing value (NULL) completeness audit
-- Purpose: Quantify dataset coverage (1950-2026) and data sparsity across key metrics.
SELECT 
    COUNT(*) AS total_models,
    MIN(publication_year) AS earliest_year,
    MAX(publication_year) AS latest_year,
    COUNT(parameters) AS valid_parameters_count,
    COUNT(training_compute_flop) AS valid_flop_count,
    COUNT(total_energy_mwh) AS valid_energy_count,
    COUNT(total_cost_usd) AS valid_cost_count,
    ROUND((CAST(COUNT(total_energy_mwh) AS FLOAT) / NULLIF(COUNT(*), 0)) * 100.0, 1) AS energy_completeness_pct,
    ROUND((CAST(COUNT(total_cost_usd) AS FLOAT) / NULLIF(COUNT(*), 0)) * 100.0, 1) AS cost_completeness_pct
FROM fact_modelos_ia;
GO

/* 
KEY INSIGHT (Stage 2A - Dataset Scope & Completeness Baseline):
- Historical Breadth vs. Metric Sparsity: Across 1,100 notable AI models (1950–2026), parameter counts (732 models, 66.5%) and compute FLOPs (544 models, 49.5%) are widely available, whereas energy footprints (174 models, 15.8%) and total budgets (180 models, 16.4%) are heavily sparse.
- Analytical Implication: Energy and emissions analyses represent a validated ~16% sample of transparent runs, making FLOP-based scaling essential for broader historical comparisons.
*/

-- 2B. Univariate summary statistics (Min, Avg, Max) for modern AI era (2018-2026)
-- Purpose: Measure compute, energy, cost, and carbon dispersion since the Transformer scaling era.
SELECT 
    ROUND(MIN(log10_flop), 2) AS min_log10_flop,
    ROUND(AVG(log10_flop), 2) AS avg_log10_flop,
    ROUND(MAX(log10_flop), 2) AS max_log10_flop,
    ROUND(AVG(total_energy_mwh), 1) AS avg_energy_mwh,
    ROUND(MAX(total_energy_mwh), 1) AS max_energy_mwh,
    ROUND(AVG(total_cost_usd), 0) AS avg_cost_usd,
    ROUND(MAX(total_cost_usd), 0) AS max_cost_usd,
    ROUND(AVG(estimated_co2_tons), 1) AS avg_co2_tons,
    ROUND(MAX(estimated_co2_tons), 1) AS max_co2_tons
FROM fact_modelos_ia
WHERE publication_year >= 2018;
GO

/* 
KEY INSIGHT (Stage 2B - Massive Gap Between Average and Frontier AI Models):
- Huge Compute Leap: The largest AI models require 1 trillion times more computing power than the smallest ones (jumping from 14.99 to 26.97 log10 FLOPs).
- Extreme Outliers: A few giant "frontier" models pull the averages way up. The most expensive training run cost $387.8M (44x higher than the $8.78M average).
- Massive Energy & Carbon Footprint: The largest training run consumed 273,112.5 MWh—enough electricity to power a medium-sized city for a year—and emitted over 100,778 tons of CO2 (54x above the average model).
*/

-- 2C. Training Cycle Duration Audit (Summary & Model-Level Disclosure)
-- Purpose: Evaluate training run lengths in days and identify disclosure gaps among frontier labs.
SELECT
    ROUND(MIN(training_time_hours) / 24.0, 1) AS min_days,
    ROUND(AVG(training_time_hours) / 24.0, 1) AS avg_days,
    ROUND(MAX(training_time_hours) / 24.0, 1) AS max_days
FROM fact_modelos_ia
WHERE training_time_hours IS NOT NULL;

SELECT
    model_name,
    organization,
    publication_year,
    ROUND(training_time_hours / 24.0, 1) AS training_days
FROM fact_modelos_ia
ORDER BY publication_year DESC, training_days DESC;
GO

/* 
KEY INSIGHT (Stage 2C - Training Duration & Industry Opacity):
- High Opacity Among Frontier Labs: The vast majority of models—specifically flagship releases from OpenAI (GPT-5/6), Google DeepMind (Gemini 3/4), Anthropic (Claude 4/5), xAI, and DeepSeek—do not disclose training duration (NULL), reflecting growing commercial secrecy in frontier AI.
- Multi-Month Frontier Runs: While pre-2018 models trained in hours or a few days (e.g., Transformer at 3.5 days, AlexNet at 5.5 days), modern disclosed frontier runs typically span 2 to 4 months (e.g., Llama 3.1-405B at 89.3 days, GPT-4 at 95 days, Gemini 1.0 Ultra at 100 days, GPT-4.5 at 125 days).
- Data Modeling Impact: Transparency in 2024–2026 comes mainly from open-weight releases and regional/academic labs (e.g., AllenAI, LG AI Research, Mistral). Consequently, energy modeling for closed models must rely on compute FLOPs rather than reported training hours.
*/

-- 2D. Full Ranking of AI Models by Energy Consumption, Cost & Emissions (Including NULLs)
-- Purpose: Rank individual models by energy footprint and contrast electricity bills against total budgets.
SELECT
    model_name, 
    publication_year, 
    ROUND(total_energy_mwh, 1) AS energy_mwh,
    ROUND(total_cost_usd, 0) AS total_cost_usd,
    ROUND(electricity_cost_usd, 0) AS electricity_cost_usd,
    ROUND(estimated_co2_tons, 1) AS co2_tons
FROM fact_modelos_ia
ORDER BY total_energy_mwh DESC;
GO

/* 
KEY INSIGHT (Stage 2D - Model-Level Energy, Cost & Emissions Ranking):
- ~84% Missing Energy Data: Out of 1,100 models, only 174 (15.8%) have energy, electricity, and CO2 figures. The rest are NULL because labs hide training hours or chip counts.
- Expensive Models Without Energy Data: Some flagship models have NULL energy/CO2 data but known total budgets—including the dataset's priciest models, Grok 4 ($387.8M) and GPT-4.5 ($366.0M), plus Llama 4 Behemoth ($44.6M) and Claude 3.5 Sonnet ($25.9M).
- Grok 3 Leads by a Wide Margin: Among models with energy data, Grok 3 (2025) ranks #1 at 273,112.5 MWh, $217.8M total cost ($23.2M electricity), and 100,778.5 tons of CO2—over 2.5x the energy of #2 Gemini 1.0 Ultra (106,050 MWh).
- Electricity Is Only ~10% of Total Cost: Where both numbers exist, power bills represent just 9%–12% of total spend (Grok 3: 10.7%; Llama 3.1-405B: 9.0%; GPT-4: 11.9%). Roughly 90% goes to GPU hardware and infrastructure.
- Location Shapes Emissions: Mistral Large 4 (trained in France) used 48% more energy than PaLM 540B (10,973 vs. 7,416 MWh) but emitted 4.5x less CO2 (614.5 vs. 2,736.5 tons) thanks to France's low-carbon nuclear grid.
*/


-- ============================================================================
-- STAGE 3: STAR SCHEMA MULTI-DIMENSIONAL ANALYSIS (Hardware & Geopolitics)
-- ============================================================================

-- 3A. Hardware Efficiency & Cluster Scale by Chip Family (Fact + dim_hardware)
-- Purpose: Compare adoption, average cluster size, and energy draw across GPU/TPU generations.
SELECT 
    h.chip_family,
    h.manufacturer,
    h.release_year,
    h.tdp_watts,
    COUNT(f.model_id) AS models_trained,
    ROUND(AVG(f.hardware_quantity), 0) AS avg_cluster_chips,
    ROUND(AVG(f.training_time_hours) / 24.0, 1) AS avg_training_days,
    ROUND(AVG(f.total_energy_mwh), 1) AS avg_energy_mwh,
    ROUND(SUM(f.total_energy_mwh), 1) AS total_energy_mwh
FROM fact_modelos_ia f
INNER JOIN dim_hardware h ON f.hardware_id = h.hardware_id
WHERE h.chip_family <> 'Other / Unspecified'
GROUP BY h.chip_family, h.manufacturer, h.release_year, h.tdp_watts
ORDER BY models_trained DESC;
GO

/* 
KEY INSIGHT (Stage 3A - Cluster Scaling Across Hardware Generations):
- NVIDIA A100 Leads Adoption, H100 Dominates Total Energy: NVIDIA A100 trained the most models (86 models, averaging 1,735 chips and 3,617 MWh per run), but NVIDIA H100 (30 models) consumed more than double the cumulative energy (362,298 MWh vs. 155,545 MWh) due to 5.1x larger average clusters (8,889 chips) and 2x longer runs (69.3 days).
- Rapid Cluster Expansion Across Generations: Average cluster size grew more than 40x from NVIDIA V100 (427 chips, 123.7 MWh avg) to NVIDIA B200 (17,819 chips, 12,548 MWh avg).
- Google's Pod-Scale Strategy: Google TPU v4 (27 models) achieved massive scale (4,271 chips on average, 117,044 MWh total) while keeping individual chip thermal draw 61% lower than H100 (275W vs. 700W).
*/

-- 3B. Geopolitical Compute Share & Cumulative Carbon Footprint by Country (Fact + dim_pais_energia)
-- Purpose: Evaluate total energy demand, electricity spending, and CO2 emissions by national grid.
SELECT 
    p.country,
    p.gco2_per_kwh,
    p.industrial_tariff_usd_kwh,
    COUNT(f.model_id) AS models_count,
    ROUND(SUM(f.total_energy_mwh), 1) AS total_energy_mwh,
    ROUND(SUM(f.estimated_co2_tons), 1) AS total_co2_tons,
    ROUND(SUM(f.electricity_cost_usd), 0) AS total_electricity_bill_usd
FROM fact_modelos_ia f
INNER JOIN dim_pais_energia p ON f.pais_id = p.pais_id
GROUP BY p.country, p.gco2_per_kwh, p.industrial_tariff_usd_kwh
ORDER BY total_energy_mwh DESC;
GO

/* 
KEY INSIGHT (Stage 3B - US Compute Dominance & European Tariff/Carbon Divergence):
- Overwhelming US Concentration (>90%): The United States accounts for 64.5% of all cataloged models (709 of 1,100) and 90.7% of all disclosed training energy (655,349 MWh) and CO2 emissions (241,824 tons), generating $55.7M in electricity bills.
- China's High-Carbon Intensity Impact: China ranks #2 in model count (165 models) and #3 in disclosed energy (13,253 MWh), but its coal-heavy grid (582 gCO2/kWh) produces 7,713 tons of CO2—12.5x more emissions than France (614.5 tons) from only 21% more energy.
- France's Clean-Grid Advantage vs. Tariff Cost: France (Mistral Large 4 at 10,973 MWh) paid $2.08M in electricity—nearly double China's total disclosed bill ($1.17M)—yet emitted 12.5x less CO2 due to its 56 gCO2/kWh nuclear grid.
*/


-- ============================================================================
-- STAGE 4: ADVANCED T-SQL ANALYTICS (CTEs, Window Functions & Organization Benchmarks)
-- ============================================================================

-- 4A. Year-over-Year (YoY) Scaling & Cumulative Carbon Emissions (CTE + LAG + Running Total)
-- Purpose: Track annual compute/energy growth rates and cumulative emissions from 2018 to 2026.
WITH annual_metrics AS (
    SELECT 
        publication_year,
        COUNT(model_id) AS models_count,
        ROUND(AVG(log10_flop), 2) AS avg_log10_flop,
        ROUND(AVG(total_energy_mwh), 1) AS avg_energy_mwh,
        ROUND(SUM(total_energy_mwh), 1) AS total_energy_mwh,
        ROUND(SUM(estimated_co2_tons), 1) AS annual_co2_tons
    FROM fact_modelos_ia
    WHERE publication_year BETWEEN 2018 AND 2026
    GROUP BY publication_year
)
SELECT 
    publication_year,
    models_count,
    avg_log10_flop,
    avg_energy_mwh,
    ROUND(
        ((avg_energy_mwh - LAG(avg_energy_mwh) OVER (ORDER BY publication_year)) 
        / NULLIF(LAG(avg_energy_mwh) OVER (ORDER BY publication_year), 0)) * 100.0, 
    1) AS yoy_avg_energy_growth_pct,
    annual_co2_tons,
    ROUND(SUM(annual_co2_tons) OVER (ORDER BY publication_year), 1) AS cumulative_co2_tons
FROM annual_metrics
ORDER BY publication_year;
GO

/* 
KEY INSIGHT (Stage 4A - Exponential Compute Scaling & Cumulative Emissions Trajectory):
- Sustained Compute Growth: Average model compute climbed steadily from 18.3 log10 FLOPs in 2018 to 24.7 in 2026—a >2.5-million-fold increase in average training compute over eight years.
- Two Major Energy Inflection Points: Average energy per training run surged +1,289.7% in 2023 (jumping from 529 MWh to 7,357 MWh with GPT-4 and Gemini 1.0 Ultra) and jumped another +257.6% in 2025 (reaching an all-time peak of 31,682 MWh avg / 285,137 MWh total, driven by Grok 3).
- Cumulative Carbon Footprint: Disclosed AI training runs between 2018 and 2026 accumulated 266,268 metric tons of CO2—with 95% of those cumulative emissions occurring from 2023 onward.
*/

-- 4B. Top 3 Most Energy-Intensive AI Models per Country (Window Function RANK)
-- Purpose: Identify national flagship models and hardware choices across major AI hubs.
WITH ranked_country_models AS (
    SELECT 
        p.country,
        f.model_name,
        f.organization,
        f.publication_year,
        h.chip_family,
        ROUND(f.total_energy_mwh, 1) AS total_energy_mwh,
        ROUND(f.estimated_co2_tons, 1) AS estimated_co2_tons,
        RANK() OVER (PARTITION BY p.country ORDER BY f.total_energy_mwh DESC) AS country_energy_rank
    FROM fact_modelos_ia f
    INNER JOIN dim_pais_energia p ON f.pais_id = p.pais_id
    INNER JOIN dim_hardware h ON f.hardware_id = h.hardware_id
    WHERE f.total_energy_mwh IS NOT NULL
      AND p.country <> 'Other / Multinational'
)
SELECT 
    country,
    country_energy_rank,
    model_name,
    organization,
    publication_year,
    chip_family,
    total_energy_mwh,
    estimated_co2_tons
FROM ranked_country_models
WHERE country_energy_rank <= 3
ORDER BY country, country_energy_rank;
GO

/* 
KEY INSIGHT (Stage 4B - National AI Champions & Hardware Sovereignty):
- Massive Scale Divide Between US and Regional Hubs: The US podium—Grok 3 (273,113 MWh), Gemini 1.0 Ultra (106,050 MWh), and Llama 3.1-405B (55,726 MWh)—operates an order of magnitude above Europe and Asia's top disclosed models: France's Mistral Large 4 (10,973 MWh), China's MegaScale (5,638 MWh), and the UK's Gopher 280B (3,930 MWh).
- Hardware Ecosystem Specialization: US leaders split between massive NVIDIA H100 clusters (xAI, Meta) and Google's proprietary TPU v4 pods (DeepMind), while China's top disclosed runs rely on A100/H100 clusters and France's Mistral Large 4 leverages next-generation NVIDIA B200 chips.
*/

-- 4C. Top 10 Organizations by Total Disclosed Energy & Carbon Footprint
-- Purpose: Rank leading AI labs by cumulative disclosed energy, CO2 emissions, and compute budgets.
SELECT TOP 10
    organization,
    COUNT(model_id) AS total_models,
    COUNT(total_energy_mwh) AS models_with_energy_data,
    ROUND(SUM(total_energy_mwh), 1) AS total_energy_mwh,
    ROUND(SUM(estimated_co2_tons), 1) AS total_co2_tons,
    ROUND(SUM(total_cost_usd), 0) AS total_disclosed_cost_usd
FROM fact_modelos_ia
WHERE organization IS NOT NULL
GROUP BY organization
ORDER BY total_energy_mwh DESC;
GO

/* 
KEY INSIGHT (Stage 4C - Lab-Level Concentration & Opacity Gap):
- Single-Model Dominance at xAI: xAI leads all organizations in cumulative disclosed energy (273,113 MWh) and CO2 (100,779 tons) from just 1 model with energy data (Grok 3), while holding the highest disclosed compute spend ($637.2M across Grok 2, 3, and 4).
- Big Tech Cumulative Footprints: OpenAI (113,044 MWh across 6 disclosed models; $415.1M total disclosed cost), Google DeepMind (106,054 MWh across 3 models), and Meta AI (62,238 MWh across 6 models) follow—though their true footprints are significantly higher because most of their 2024–2026 flagship models withhold training duration.
- Sovereign & Non-US Contenders: Abu Dhabi's Technology Innovation Institute (Falcon-40B/180B at 16,678 MWh) and France's Mistral AI (Mistral Large 4 at 10,973 MWh) are the only non-US organizations in the global top 10.
*/