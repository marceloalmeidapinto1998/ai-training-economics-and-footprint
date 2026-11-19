import os
from datetime import datetime, timezone
import pandas as pd
from config import get_sql_engine

BRONZE_DIR = "data/01_bronze_raw"

def clean_col_names(df: pd.DataFrame) -> pd.DataFrame:
    df.columns = [
        c.strip()
         .replace(" ", "_")
         .replace("(", "")
         .replace(")", "")
         .replace("/", "_")
         .replace("-", "_")
         .replace("%", "pct")
         .replace("@", "_at_")
        for c in df.columns
    ]
    return df

def load_csv_to_staging(file_path: str, table_name: str, engine, ingested_at: str):
    if not os.path.exists(file_path):
        print(f"[WARN] Missing file: {file_path}")
        return
    df = pd.read_csv(file_path)
    df = clean_col_names(df)
    df["_ingested_at_utc"] = ingested_at
    df["_source_file"] = os.path.basename(file_path)
    
    df.to_sql(table_name, engine, schema="dbo", if_exists="replace", index=False)
    print(f"[OK] {table_name:<28} <- {len(df):>5} rows ({os.path.basename(file_path)})")

def run_bronze_load():
    engine = get_sql_engine()
    ingested_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    print(f"=== Loading Bronze Layer to SQL Server ({ingested_at} UTC) ===")

    # 1. Core Datasets & Reference Tables
    files_to_load = {
        os.path.join(BRONZE_DIR, "notable_ai_models.csv"): "stg_epoch_models",
        os.path.join(BRONZE_DIR, "ml_hardware.csv"): "stg_epoch_hardware",
        os.path.join(BRONZE_DIR, "grid_intensity_wue.csv"): "stg_grid_intensity_wue",
        # Curated Frontier Benchmarks
        os.path.join(BRONZE_DIR, "epoch_benchmarks_raw", "model_metadata.csv"): "stg_bench_model_metadata",
        os.path.join(BRONZE_DIR, "epoch_benchmarks_raw", "gpqa_diamond.csv"): "stg_bench_gpqa_diamond",
        os.path.join(BRONZE_DIR, "epoch_benchmarks_raw", "frontiermath.csv"): "stg_bench_frontiermath",
        os.path.join(BRONZE_DIR, "epoch_benchmarks_raw", "swe_bench_verified.csv"): "stg_bench_swe_bench",
        os.path.join(BRONZE_DIR, "epoch_benchmarks_raw", "mmlu_external.csv"): "stg_bench_mmlu",
        os.path.join(BRONZE_DIR, "epoch_benchmarks_raw", "webdev_arena_external.csv"): "stg_bench_arena",
    }

    for path, table_name in files_to_load.items():
        load_csv_to_staging(path, table_name, engine, ingested_at)

    print("=== Bronze Load Complete ===")

if __name__ == "__main__":
    run_bronze_load()
