import os
import pandas as pd
from config import get_sql_engine

GOLD_EXPORT_DIR = "data/02_gold_exports"

def export_gold_views():
    os.makedirs(GOLD_EXPORT_DIR, exist_ok=True)
    engine = get_sql_engine()

    print("=== Exporting Gold Layer Marts to CSV ===")
    df_gold = pd.read_sql("SELECT * FROM dbo.vw_models_enriched", engine)
    out_path = os.path.join(GOLD_EXPORT_DIR, "models_enriched_gold.csv")
    df_gold.to_csv(out_path, index=False)
    print(f"[OK] Exported {len(df_gold)} rows & {len(df_gold.columns)} columns -> {out_path}")

if __name__ == "__main__":
    export_gold_views()
