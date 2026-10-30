from pathlib import Path
import pandas as pd

DATA = Path(__file__).resolve().parents[1] / "data"

def main():
    results = []
    for path in sorted(DATA.glob("*.csv")):
        df = pd.read_csv(path)
        results.append({
            "dataset": path.name,
            "rows": len(df),
            "columns": len(df.columns),
            "exact_duplicate_rows": int(df.duplicated().sum()),
            "missing_cells": int(df.isna().sum().sum()),
            "missing_pct": round(df.isna().sum().sum() / max(df.size, 1) * 100, 2),
        })
    out = pd.DataFrame(results)
    print(out.to_string(index=False))
    out.to_csv(Path("data_profile.csv"), index=False)

if __name__ == "__main__":
    main()
