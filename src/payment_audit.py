from pathlib import Path
import pandas as pd

DATA = Path(__file__).resolve().parents[1] / "data"

def main():
    p = pd.read_csv(DATA / "payments.csv")
    p["amount"] = pd.to_numeric(p["amount"], errors="coerce")
    print("Rows:", len(p))
    print("\nPayment status:")
    print(p["payment_status"].value_counts(dropna=False).to_string())
    print("\nExact duplicate rows:", int(p.duplicated().sum()))
    ref = p.groupby("payment_reference", dropna=False).agg(
        rows=("payment_id", "size"),
        distinct_accounts=("account_id", "nunique"),
        distinct_amounts=("amount", "nunique"),
        distinct_statuses=("payment_status", "nunique"),
        total_amount=("amount", "sum"),
    )
    repeated = ref[ref["rows"] > 1]
    print("\nRepeated-reference groups:", len(repeated))
    print("Rows in repeated-reference groups:", int(repeated["rows"].sum()))
    print("Repeated references across multiple accounts:", int((repeated["distinct_accounts"] > 1).sum()))
    print("Repeated references with multiple statuses:", int((repeated["distinct_statuses"] > 1).sum()))
    # Do not automatically deduplicate on payment_reference alone:
    # a repeated reference can occur across accounts or statuses and needs investigation.
    repeated.to_csv("payment_reference_audit.csv")
    print("\nAudit saved to payment_reference_audit.csv")

if __name__ == "__main__":
    main()
