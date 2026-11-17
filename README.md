# EpochAI Sustainability & FinOps Analytics (`EpochAI_DW`)

An end-to-end **Data Engineering & Executive Analytics** project analyzing the computational growth, energy footprint, capital expenditure (CapEx vs. OpEx), carbon emissions, and commercial transparency gap of notable AI models (2015–2026).

---

## Executive Summary & Key Findings

1. **The AI Transparency Gap:** While median carbon emissions per disclosed model surged past **1,600 metric tons of $\text{CO}_2$** in 2026, industry energy disclosure dropped from **32% (2022)** to **5% (2026 YTD)** as frontier development shifted toward closed commercial APIs.
2. **Hardware Efficiency vs. Cluster Scale:** Newer accelerators (NVIDIA H100/B200, Google TPUs) consume more total power due to massive cluster sizes, yet require significantly **less energy per $10^{24}$ operations** than legacy GPUs.
3. **FinOps Budget Structure (~90% CapEx / ~10% OpEx):** Across disclosed training budgets, hardware and cluster infrastructure account for **~90%** of total costs, while pure electricity bills represent **~10%**.
4. **Predictive Scaling ($R^2$):** Log-linear regression across disclosed models reliably projects the hidden energy demand of major closed frontier releases from their reported compute scale (`FLOPs`).
5. **Geopolitical Site Selection:** A **50,000 MWh** *what-if* simulation highlights **Canada** as an optimal training hub balancing low industrial electricity tariffs with clean hydro/nuclear grid intensity.

---

## Architecture & Tech Stack

* **Database & Data Modeling:** SQL Server (`EpochAI_DW`) structured as a **Star Schema** (`Fact_AI_Models`, `Dim_Organization`, `Dim_Hardware`, `Dim_Country_Grid`) with analytical semantic views (`vw_ai_models_master`, `vw_annual_energy_trends`).
* **Data Wrangling & Analytics:** Python (`pandas`, `numpy`, `SQLAlchemy`, `pyodbc`) handling severe data sparsity (~84% missing energy disclosures) via median normalization and log-linear regression.
* **Data Visualization:** Interactive executive charts built with **Plotly** and **Power BI Desktop**.

---

## Visual Analytics Gallery

### 1. Scaling Laws & The Reporting Transparency Gap
![Scaling Laws & Transparency](images/chart1_scaling_transparency.png)

### 2. Energy Consumption vs. Compute Efficiency (Top 12 Models)
![Energy vs Efficiency](images/chart2_energy_efficiency.png)

### 3. Training Budget Breakdown (Hardware CapEx vs. Electricity OpEx)
![Training Cost Structure](images/chart3_cost_structure.png)

### 4. Predictive Scaling Regression & Hidden Frontier Demand
![Predictive Scaling](images/chart4_predictive_scaling.png)

### 5. Geopolitical Grid Trade-Off & 50,000 MWh Site Simulation
![Geopolitical Grid](images/chart5_geopolitical_grid.png)

### 6. AI Governance: Open-Weights vs. Closed Commercial Releases
![Governance Risk](images/chart6_governance_risk.png)

### 7. Competitive Landscape: Top 10 AI Labs
![Competitive Landscape](images/chart7_competitive_landscape.png)

---

## How to Reproduce

1. **Build the SQL Server Data Warehouse:**
   Execute the scripts in `sql/` sequentially (`00_setup_database.sql` through `03_views_analise_models.sql`) in SQL Server Management Studio (SSMS) or Azure Data Studio.
2. **Configure Python Environment:**
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt