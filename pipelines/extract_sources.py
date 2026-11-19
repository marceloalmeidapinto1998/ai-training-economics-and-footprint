import os
import io
import zipfile
import urllib.request
import pandas as pd

BRONZE_DIR = "data/01_bronze_raw"

def extract_all_sources():
    os.makedirs(BRONZE_DIR, exist_ok=True)
    print("--- 1. Extracting Epoch AI ML Hardware Dataset ---")
    hw_df = pd.read_csv("https://epoch.ai/data/ml_hardware.csv")
    hw_path = os.path.join(BRONZE_DIR, "ml_hardware.csv")
    hw_df.to_csv(hw_path, index=False)
    print(f"[OK] Saved {len(hw_df)} rows -> {hw_path}")

    print("--- 2. Extracting Regional Grid Carbon, Tariffs & Water (WUE) ---")
    owid_url = "https://raw.githubusercontent.com/owid/energy-data/master/owid-energy-data.csv"
    owid = pd.read_csv(owid_url, usecols=["country", "year", "carbon_intensity_elec"]).dropna()
    latest_c = dict(owid.sort_values("year").groupby("country").last()["carbon_intensity_elec"])

    grid_df = pd.DataFrame([
        {"Region_Code": "US-VA", "Country": "United States (Virginia)", "Carbon_gCO2_kWh": 315.0, "Tariff_USD_MWh": 82.0, "WUE_Liters_kWh": 1.80, "Default_Facility_PUE": 1.20, "Source_Citation": "US EPA eGRID (SRVC) / EIA Industrial / Evaporative WUE Benchmark"},
        {"Region_Code": "US-TX", "Country": "United States (Texas)", "Carbon_gCO2_kWh": 385.0, "Tariff_USD_MWh": 68.0, "WUE_Liters_kWh": 2.10, "Default_Facility_PUE": 1.25, "Source_Citation": "US EPA eGRID (ERCT) / EIA Industrial / Li et al. Thermal Cooling"},
        {"Region_Code": "CA-QC", "Country": "Canada (Quebec)", "Carbon_gCO2_kWh": 12.0, "Tariff_USD_MWh": 45.0, "WUE_Liters_kWh": 0.45, "Default_Facility_PUE": 1.12, "Source_Citation": "Canada NIR / Hydro-Quebec Industrial / Free-Cooling WUE"},
        {"Region_Code": "SE-NORD", "Country": "Sweden", "Carbon_gCO2_kWh": round(latest_c.get("Sweden", 36.0), 1), "Tariff_USD_MWh": 96.0, "WUE_Liters_kWh": 0.30, "Default_Facility_PUE": 1.10, "Source_Citation": "Ember OWID Energy / Microsoft & Meta Nordic WUE"},
        {"Region_Code": "EU-DE", "Country": "Germany", "Carbon_gCO2_kWh": round(latest_c.get("Germany", 340.0), 1), "Tariff_USD_MWh": 165.0, "WUE_Liters_kWh": 1.15, "Default_Facility_PUE": 1.22, "Source_Citation": "Ember OWID Energy / Eurostat Industrial / Google Fleet WUE"},
        {"Region_Code": "UK-LON", "Country": "United Kingdom", "Carbon_gCO2_kWh": round(latest_c.get("United Kingdom", 209.0), 1), "Tariff_USD_MWh": 195.0, "WUE_Liters_kWh": 0.95, "Default_Facility_PUE": 1.18, "Source_Citation": "Ember OWID Energy / UK DESNZ Industrial Tariff"},
        {"Region_Code": "CN-EAST", "Country": "China", "Carbon_gCO2_kWh": round(latest_c.get("China", 545.0), 1), "Tariff_USD_MWh": 76.0, "WUE_Liters_kWh": 2.35, "Default_Facility_PUE": 1.32, "Source_Citation": "Ember OWID Energy / Li et al. High-Ambient WUE"}
    ])
    grid_path = os.path.join(BRONZE_DIR, "grid_intensity_wue.csv")
    grid_df.to_csv(grid_path, index=False)
    print(f"[OK] Saved {len(grid_df)} rows -> {grid_path}")

    print("--- 3. Extracting Epoch AI Official Capabilities & Benchmarks ---")
    bench_dir = os.path.join(BRONZE_DIR, "epoch_benchmarks_raw")
    os.makedirs(bench_dir, exist_ok=True)
    req = urllib.request.urlopen("https://epoch.ai/data/benchmark_data.zip")
    with zipfile.ZipFile(io.BytesIO(req.read())) as zf:
        zf.extractall(bench_dir)
    print(f"[OK] Extracted files -> {os.listdir(bench_dir)}")

if __name__ == "__main__":
    extract_all_sources()
