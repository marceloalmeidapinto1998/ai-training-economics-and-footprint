import os
import nbformat as nbf

os.makedirs("analysis", exist_ok=True)
os.makedirs("assets/charts", exist_ok=True)

# ==============================================================================
# NOTEBOOK 1: Physics-Informed Energy Imputation & Scaling Uncertainty
# ==============================================================================
nb1 = nbf.v4.new_notebook()
nb1.cells = [
    nbf.v4.new_markdown_cell(
        "# 01. Physics-Informed Energy Imputation & Scaling Uncertainty\n"
        "**Objective:** Address the ~84% missing hardware/energy telemetry in Epoch AI's dataset by modeling "
        "$\\log_{10}(\\text{Facility Energy MWh}) \\sim \\log_{10}(\\text{Training Compute FLOP})$ with **80% and 95% Prediction Intervals**."
    ),
    nbf.v4.new_code_cell(
        "import os\n"
        "import numpy as np\n"
        "import pandas as pd\n"
        "import statsmodels.api as sm\n"
        "import plotly.graph_objects as go\n\n"
        "df = pd.read_csv('../data/02_gold_exports/models_enriched_gold.csv')\n"
        "valid = df.dropna(subset=['training_compute_flop', 'facility_total_energy_mwh']).copy()\n"
        "valid = valid[(valid['training_compute_flop'] > 0) & (valid['facility_total_energy_mwh'] > 0)]\n\n"
        "valid['log_flop'] = np.log10(valid['training_compute_flop'])\n"
        "valid['log_energy'] = np.log10(valid['facility_total_energy_mwh'])\n"
        "print(f'Total Gold models: {len(df)} | Physics-verified training runs: {len(valid)} ({len(valid)/len(df):.1%})')"
    ),
    nbf.v4.new_code_cell(
        "# Fit OLS Log-Linear Scaling Law with 80% and 95% Prediction Intervals\n"
        "X = sm.add_constant(valid['log_flop'])\n"
        "model = sm.OLS(valid['log_energy'], X).fit()\n"
        "print(model.summary())\n\n"
        "x_grid = np.linspace(valid['log_flop'].min(), valid['log_flop'].max(), 200)\n"
        "X_pred = sm.add_constant(x_grid)\n"
        "pred_95 = model.get_prediction(X_pred).summary_frame(alpha=0.05)\n"
        "pred_80 = model.get_prediction(X_pred).summary_frame(alpha=0.20)\n\n"
        "# Apply imputation to undisclosed models that report FLOPs\n"
        "missing_energy = df[df['facility_total_energy_mwh'].isna() & (df['training_compute_flop'] > 0)].copy()\n"
        "missing_energy['log_flop'] = np.log10(missing_energy['training_compute_flop'])\n"
        "imp_pred = model.get_prediction(sm.add_constant(missing_energy['log_flop'])).summary_frame(alpha=0.05)\n"
        "missing_energy['imputed_energy_mwh_p50'] = 10 ** imp_pred['mean']\n"
        "missing_energy['imputed_energy_mwh_low95'] = 10 ** imp_pred['obs_ci_lower']\n"
        "missing_energy['imputed_energy_mwh_high95'] = 10 ** imp_pred['obs_ci_upper']\n\n"
        "print(f'Imputed energy bounds for {len(missing_energy)} undisclosed models.')\n"
        "missing_energy[['model_name', 'organization', 'publication_year', 'imputed_energy_mwh_p50', 'imputed_energy_mwh_low95', 'imputed_energy_mwh_high95']].sort_values('imputed_energy_mwh_p50', ascending=False).head(10)"
    ),
    nbf.v4.new_code_cell(
        "# Executive Visualization: Chart 8 - Energy Scaling Law & Prediction Uncertainty\n"
        "fig = go.Figure()\n"
        "fig.add_trace(go.Scatter(x=x_grid, y=10**pred_95['obs_ci_upper'], mode='lines', line=dict(width=0), showlegend=False))\n"
        "fig.add_trace(go.Scatter(x=x_grid, y=10**pred_95['obs_ci_lower'], mode='lines', line=dict(width=0), fill='tonexty', fillcolor='rgba(59, 130, 246, 0.12)', name='95% Prediction Interval'))\n"
        "fig.add_trace(go.Scatter(x=x_grid, y=10**pred_80['obs_ci_upper'], mode='lines', line=dict(width=0), showlegend=False))\n"
        "fig.add_trace(go.Scatter(x=x_grid, y=10**pred_80['obs_ci_lower'], mode='lines', line=dict(width=0), fill='tonexty', fillcolor='rgba(59, 130, 246, 0.25)', name='80% Prediction Interval'))\n"
        "fig.add_trace(go.Scatter(x=x_grid, y=10**pred_95['mean'], mode='lines', line=dict(color='#2563EB', width=2.5), name=f'Log-Linear Fit (R^2 = {model.rsquared:.2f})'))\n"
        "fig.add_trace(go.Scatter(\n"
        "    x=valid['log_flop'], y=valid['facility_total_energy_mwh'], mode='markers',\n"
        "    text=valid['model_name'], marker=dict(size=7, color='#0F172A', opacity=0.75),\n"
        "    name='Disclosed Hardware Telemetry'\n"
        "))\n"
        "fig.update_layout(\n"
        "    title='Physics-Informed Energy Scaling Law & Imputation Uncertainty Bands',\n"
        "    xaxis_title='Training Compute (log10 FLOP)',\n"
        "    yaxis_title='Facility Total Energy (MWh, PUE-Adjusted)',\n"
        "    yaxis_type='log', template='plotly_white', width=1050, height=580\n"
        ")\n"
        "fig.write_image('../assets/charts/chart8_imputation_uncertainty.png', scale=2)\n"
        "fig.show()"
    )
]
with open("analysis/01_imputation_and_scaling.ipynb", "w", encoding="utf-8") as f:
    nbf.write(nb1, f)

# ==============================================================================
# NOTEBOOK 2: Pareto Efficiency Frontier & 12-Month Inference TCO Model
# ==============================================================================
nb2 = nbf.v4.new_notebook()
nb2.cells = [
    nbf.v4.new_markdown_cell(
        "# 02. Pareto Efficiency Frontier & 12-Month Inference TCO Model\n"
        "**Objective:** Evaluate **Capability-per-Dollar** and **Capability-per-Ton-CO2** across frontier models, "
        "and model full lifecycle TCO (Pre-Training CapEx/OpEx + 12-Month Serving Inference)."
    ),
    nbf.v4.new_code_cell(
        "import numpy as np\n"
        "import pandas as pd\n"
        "import plotly.express as px\n"
        "import plotly.graph_objects as go\n\n"
        "df = pd.read_csv('../data/02_gold_exports/models_enriched_gold.csv')\n"
        "pareto_df = df.dropna(subset=['Composite_Capability_Index', 'total_cost_usd']).copy()\n"
        "pareto_df = pareto_df[(pareto_df['Composite_Capability_Index'] > 0) & (pareto_df['total_cost_usd'] > 0)]\n\n"
        "# Compute Pareto Frontier (Minimize Cost, Maximize Composite Capability Index)\n"
        "pareto_df = pareto_df.sort_values('total_cost_usd')\n"
        "frontier_rows = []\n"
        "max_cap = -1.0\n"
        "for _, row in pareto_df.iterrows():\n"
        "    if row['Composite_Capability_Index'] > max_cap:\n"
        "        frontier_rows.append(row)\n"
        "        max_cap = row['Composite_Capability_Index']\n"
        "frontier = pd.DataFrame(frontier_rows)\n"
        "print(f'Models evaluated: {len(pareto_df)} | Pareto-optimal models: {len(frontier)}')\n"
        "frontier[['model_name', 'organization', 'publication_year', 'total_cost_usd', 'Composite_Capability_Index', 'usd_per_capability_point', 'co2_tons_per_capability_point']]"
    ),
    nbf.v4.new_code_cell(
        "# Chart 9: Frontier Capability vs. Training Cost Pareto Curve\n"
        "fig = px.scatter(\n"
        "    pareto_df, x='total_cost_usd', y='Composite_Capability_Index',\n"
        "    color='organization', hover_name='model_name',\n"
        "    size=pareto_df['facility_total_energy_mwh'].fillna(pareto_df['facility_total_energy_mwh'].median()), log_x=True,\n"
        "    title='AI Economics Pareto Frontier: Capability Index vs. Training Cost (USD)',\n"
        "    labels={'total_cost_usd': 'Estimated Training Cost (USD, Log Scale)', 'Composite_Capability_Index': 'Composite Frontier Capability Index (0-100)'},\n"
        "    template='plotly_white', width=1050, height=580\n"
        ")\n"
        "fig.add_trace(go.Scatter(\n"
        "    x=frontier['total_cost_usd'], y=frontier['Composite_Capability_Index'],\n"
        "    mode='lines+markers+text', text=frontier['model_name'], textposition='top left',\n"
        "    line=dict(color='#DC2626', width=2.5, dash='dash'),\n"
        "    marker=dict(size=10, color='#DC2626', symbol='diamond'),\n"
        "    name='Pareto Efficiency Frontier'\n"
        "))\n"
        "fig.write_image('../assets/charts/chart9_pareto_frontier.png', scale=2)\n"
        "fig.show()"
    ),
    nbf.v4.new_code_cell(
        "# 12-Month Lifecycle TCO Simulator (Pre-Training + Production Inference Serving)\n"
        "def simulate_12m_tco(df_models, daily_requests=10_000_000, avg_output_tokens=500, watts_per_1k_tokens=0.45):\n"
        "    sim = df_models.dropna(subset=['total_cost_usd', 'facility_total_energy_mwh']).copy()\n"
        "    annual_tokens_k = (daily_requests * avg_output_tokens * 365) / 1000.0\n"
        "    # Scale inference energy modestly with model parameter count (normalized to 70B baseline)\n"
        "    param_factor = np.log10(sim['parameters'].fillna(7e10).clip(lower=1e9)) / np.log10(7e10)\n"
        "    sim['annual_inference_mwh'] = (annual_tokens_k * watts_per_1k_tokens * param_factor) / 1e6 * sim['facility_pue']\n"
        "    sim['annual_inference_electricity_usd'] = sim['annual_inference_mwh'] * sim['tariff_usd_mwh']\n"
        "    sim['annual_inference_co2_tons'] = (sim['annual_inference_mwh'] * 1000.0 * sim['carbon_gco2_kwh']) / 1e6\n"
        "    sim['inference_to_training_energy_ratio'] = sim['annual_inference_mwh'] / sim['facility_total_energy_mwh']\n"
        "    return sim[['model_name', 'organization', 'facility_total_energy_mwh', 'annual_inference_mwh', 'inference_to_training_energy_ratio', 'total_cost_usd', 'annual_inference_electricity_usd']]\n\n"
        "tco_summary = simulate_12m_tco(df)\n"
        "tco_summary.sort_values('facility_total_energy_mwh', ascending=False).head(10)"
    )
]
with open("analysis/02_pareto_and_tco_models.ipynb", "w", encoding="utf-8") as f:
    nbf.write(nb2, f)

print("[OK] Generated analysis/01_imputation_and_scaling.ipynb and analysis/02_pareto_and_tco_models.ipynb")
