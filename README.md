# AI Training Costs, Energy & Carbon Footprint

[![SQL Server](https://img.shields.io/badge/Database-SQL%20Server-CC2927?logo=microsoftsqlserver&logoColor=white)](https://www.microsoft.com/sql-server)
[![Python](https://img.shields.io/badge/Analytics-Python%203.11-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Plotly](https://img.shields.io/badge/Visualization-Plotly-3F4F75?logo=plotly&logoColor=white)](https://plotly.com/)

An end-to-end **Data Engineering and Analytics** project measuring how much it costs—both financially (**FinOps**) and environmentally (**ESG**)—to train modern AI models from 2015 to 2026. Built on a **SQL Server Star Schema Data Warehouse (`EpochAI_DW`)** and analyzed through **Python** statistical modeling and interactive **Plotly** visualizations.

---

## Executive Summary & Key Findings

* **The AI Transparency Gap:** While median carbon emissions per disclosed model surged past **1,600 metric tons of $\text{CO}_2$** in 2026, public energy disclosure across the industry dropped from **32% (2022)** to **5% (2026 YTD)** as frontier development shifted toward closed commercial APIs.
* **Cluster Scale vs. Hardware Efficiency:** Newer accelerators (NVIDIA H100/H200/B200 and Google TPUs) draw more total electricity due to massive cluster sizes, yet require significantly **less energy per $10^{24}$ operations** than legacy GPUs.
* **Training Budget Breakdown (~90% CapEx / ~10% OpEx):** Across disclosed frontier budgets, hardware and cluster infrastructure account for **~90%** of total capital expenditure, whereas pure electricity bills represent **~10%**.
* **Predictive Scaling Laws ($R^2$):** Log-linear regression across disclosed models enables reliable estimation of the hidden energy demand of major closed frontier releases using their reported compute scale (`FLOPs`).
* **Geopolitical Site Selection:** A **50,000 MWh** *what-if* simulation highlights **Canada** as an optimal training hub balancing low industrial electricity tariffs with clean hydro/nuclear grid carbon intensity.
* **Market Concentration & Governance:** The top 10 AI laboratories account for the vast majority of notable model releases, with sharp disparities in environmental reporting transparency between open-weights and closed commercial releases.

---

## Data Architecture & Tech Stack

### 1. SQL Server Data Warehouse (`EpochAI_DW`)
Raw data from Epoch AI is transformed into a dimensional **Star Schema** optimized for analytical querying:
* **Fact Table (`Fact_AI_Models`):** Stores training compute (`FLOPs`), training duration (hours), cluster size, hardware/electricity cost estimates, energy consumption (`MWh`), and estimated $\text{CO}_2$ emissions (metric tons).
* **Dimension Tables:**
  * `Dim_Organization`: Leading AI laboratories, research institutions, and organizational metadata.
  * `Dim_Hardware`: GPU/TPU accelerator generations, TDP (Thermal Design Power), and compute efficiency specs.
  * `Dim_Country_Grid`: National grid carbon intensity ($\text{gCO}_2\text{/kWh}$) and industrial electricity tariffs ($\text{USD/kWh}$).
* **Semantic Views (`vw_ai_models_master`, `vw_annual_energy_trends`):** Pre-joined analytical views handling unit conversions, household energy equivalents, and annual aggregations.

### 2. Python Analytics & Visualization (`04-notebooks/05_eda_visualizacao.ipynb`)
* **Data Wrangling (`pandas`, `numpy`, `SQLAlchemy`, `pyodbc`):** Connects directly to SQL Server, handles severe data sparsity (~84% missing energy disclosures) using median normalization, and builds statistical regressions.
* **Visual Storytelling (`Plotly`):** Generates 7 multi-panel executive charts with zero label overlap and consistent FinOps/ESG color encoding.

---

## Repository Structure

```text
ai-training-economics-and-footprint/
├── 01-sql/
│   ├── 00_setup_database.sql          # Creates the EpochAI_DW database
│   ├── 01_create_star_schema.sql      # Star Schema DDL (Fact & Dimension tables)
│   ├── 02_etl_load_data.sql           # Data cleaning, NULL handling, and ETL load
│   ├── 03_views_analise_models.sql    # Semantic views (vw_ai_models_master)
│   └── 04_business_queries.sql        # Executive FinOps & ESG SQL queries
├── 04-notebooks/
│   └── 05_eda_visualizacao.ipynb      # Main analysis notebook with all 7 Plotly charts
├── data/
│   └── notable_ai_models.csv          # Source dataset (Epoch AI)
├── images/
│   ├── chart1_scaling_transparency.png
│   ├── chart2_energy_efficiency.png
│   ├── chart3_cost_structure.png
│   ├── chart4_predictive_scaling.png
│   ├── chart5_geopolitical_grid.png
│   ├── chart6_governance_risk.png
│   └── chart7_competitive_landscape.png
├── .gitignore
├── requirements.txt
└── README.md
```

---

## Visual Analytics Gallery

### 1. Scaling Laws & The Reporting Transparency Gap (2018–2026)
Tracks median carbon emissions per model alongside compute growth ($\log_{10}\text{ FLOP}$) and declining industry energy disclosure rates.

![Scaling Laws and Transparency](./images/chart1_scaling_transparency.png)

### 2. Energy Consumption vs. Compute Efficiency (Top 12 Models)
Compares total training energy (`MWh`) against energy intensity (`MWh` per $10^{24}$ operations) to separate cluster scale from hardware efficiency.

![Energy vs Efficiency](./images/chart2_energy_efficiency.png)

### 3. Training Budget Breakdown: Hardware CapEx (~90%) vs. Electricity OpEx (~10%)
Quantifies capital allocation between hardware/cluster infrastructure CapEx and pure electricity OpEx across top disclosed training budgets.

![Training Cost Structure](./images/chart3_cost_structure.png)

### 4. Predictive Scaling Regression & Estimated Undisclosed Frontier Models
Fits a log-linear scaling model ($R^2$) with a $\pm 1\text{ SD}$ confidence corridor to project the estimated energy demand of major undisclosed frontier releases.

![Predictive Scaling Regression](./images/chart4_predictive_scaling.png)

### 5. Geopolitical Grid Trade-Off & 50,000 MWh Site Simulation
Contrasts historical national training footprints with a 50,000 MWh *what-if* simulation comparing industrial electricity tariffs against grid carbon intensity.

![Geopolitical Grid Trade-Off](./images/chart5_geopolitical_grid.png)

### 6. AI Governance & Risk: Open-Weights vs. Closed Commercial Releases
Examines how the market shift from open-weights to closed commercial API releases drives the environmental reporting gap.

![AI Governance and Risk](./images/chart6_governance_risk.png)

### 7. Competitive Landscape: Top 10 AI Labs (Scale vs. Transparency)
Benchmarks leading organizations by notable model output, peak compute scale, and energy disclosure transparency.

![Competitive Landscape](./images/chart7_competitive_landscape.png)

---

## How to Reproduce

### Prerequisites
* **Microsoft SQL Server** (Express, Developer, or Enterprise) + **SQL Server Management Studio (SSMS)** or **Azure Data Studio**
* **Python 3.10+** with **ODBC Driver 17 or 18 for SQL Server**

### Step-by-Step Setup

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/marceloalmeidapinto1998/ai-training-economics-and-footprint.git
   cd ai-training-economics-and-footprint
   ```

2. **Build the SQL Server Data Warehouse:**
   Open SSMS or Azure Data Studio and execute the scripts inside `01-sql/` in numerical order:
   * `00_setup_database.sql`
   * `01_create_star_schema.sql`
   * `02_etl_load_data.sql`
   * `03_views_analise_models.sql`

3. **Configure the Python Environment:**
   ```bash
   python -m venv .venv
   .venv\Scripts\activate      # On macOS/Linux: source .venv/bin/activate
   pip install -r requirements.txt
   ```

4. **Run the Visualization Notebook:**
   * Open `04-notebooks/05_eda_visualizacao.ipynb` in VS Code or Jupyter.
   * In the database connection cell, update `SERVER_NAME` to match your local SQL Server instance (e.g., `r"localhost\SQLEXPRESS"`).
   * Click **Run All** to generate all interactive charts.

---

## Data Source & Acknowledgments

* **Dataset:** [Epoch AI — Notable AI Models Database](https://epoch.ai/data/notable-ai-models), providing curated records on training compute, hardware systems, training duration, and model accessibility.