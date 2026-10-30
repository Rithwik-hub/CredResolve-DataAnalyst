# CredResolve Data Analyst Assignment

## Candidate Submission | 31 October 2026

---

## Repository Structure

`
.
|-- CredResolve_Complete_Analysis.ipynb  # Main analysis notebook (10 sections)
|-- EXECUTIVE_MEMO.md                    # 2-page executive memo
|-- ARCHITECTURE.md                      # Production analytics architecture
|-- DATA_QUALITY_INITIAL.md              # First-pass data quality findings
|-- requirements.txt                     # Python dependencies
|-- data/                                # Raw CSV datasets (18 tables)
|   |-- README.md                        # Dataset notes
|   |-- data_dictionary.csv
|   |-- accounts.csv, borrowers.csv, agents.csv ...
|-- sql/
|   |-- 01_payment_forensics.sql         # Initial forensics SQL
|   |-- 02_full_analytics_suite.sql      # Full production SQL (Parts 1-5)
|-- src/
|   |-- profile_data.py                  # Reproducible table profiler
|   |-- payment_audit.py                 # Payment reference auditor
`

---

## Quick Start

`ash
python -m venv .venv
# Windows: .venv\Scripts\activate
pip install -r requirements.txt
jupyter notebook CredResolve_Complete_Analysis.ipynb
`

---

## Assignment Coverage

| Deliverable | File | Status |
|---|---|---|
| SQL Repository | sql/01_payment_forensics.sql, sql/02_full_analytics_suite.sql | Done |
| Analysis Notebook | CredResolve_Complete_Analysis.ipynb | Done |
| Golden Dataset Pipeline | Section 2 of notebook + SQL | Done |
| Data Quality Report | DATA_QUALITY_INITIAL.md + notebook Section 1 | Done |
| Executive Dashboard | Notebook Section 10 (credresolve_dashboard.png) | Done |
| Executive Memo | EXECUTIVE_MEMO.md | Done |
| Architecture Diagram | ARCHITECTURE.md | Done |

---

## Key Findings (Summary)

### 1. What happened?
- Net recovery (Jan-Jul 2026): Rs 129.1 Cr on Rs 1,048.9 Cr portfolio (43.8% recovery rate)
- Month-on-month trend: +0.3% average (essentially flat), NOT 11%
- Aug 2026 data is partial (8 days only -- excluded from MoM analysis)

### 2. Why did it happen?
- Call answer rate is only ~20% -- majority of effort produces no contact
- PTP broken rate is ~25% -- significant cash-flow leakage
- WhatsApp payment-click is the highest-intent signal but underutilised
- 8,000 complaints including 1,968 critical + 1,126 harassment = regulatory risk

### 3. Is the 11% improvement real?
**VERDICT: Not supported by the data.**
- Average MoM change: +0.3% (statistically indistinguishable from zero)
- The claim may reflect: a specific one-month spike, denominator manipulation (accounts
  exiting eligible pool), uncleaned reversal/duplicate payments, or timezone misallocation

### 4. Where to invest Rs 10 Cr?
**Recommendation: WhatsApp/Digital Engagement (Option 5)**
- Lowest cost per contact, highest intent signal (payment-click)
- PTP automation can reduce broken PTP rate from ~25%
- Expected incremental recovery: Rs 8-15 Cr over 12 months
- ROI: 0.8x-1.5x | Break-even: 8-15 months
- See EXECUTIVE_MEMO.md for full ROI model

---

## Data Quality Issues Found

| Issue | Tables | Impact |
|---|---|---|
| Exact duplicate rows | borrowers(600), calls(1271), payments(486), wa(600) | Double-counting |
| Repeated payment_reference (3,745 groups, 8,424 rows) | payments | Overstated recovery |
| Mixed timezones UTC/IST/GST | calls, accounts, agent_sessions | Wrong-month allocation |
| Missing cells | call_attempts(2400), borrowers(1509), calls(1827) | Analysis gaps |
| Legacy + current disposition codes | call_dispositions | PTP under-identification |
| Suspended agents in call logs | calls, agents | Compliance flag |

---

## Important Notes

1. **payment_reference is NOT a safe deduplication key** -- see sql/01_payment_forensics.sql
2. **Event window is ~7.5 months (Jan-Aug 2026)**, not 12 months as stated
3. **Timezone normalisation is required** before any hour-of-day or cross-month analysis
4. Raw data is preserved; golden layer is a separate view with full audit trail
