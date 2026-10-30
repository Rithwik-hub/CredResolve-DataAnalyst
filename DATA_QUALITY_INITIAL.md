# CredResolve Data Analyst — Initial Data Profiling

## Scope
This report describes the supplied synthetic collections dataset and the first-pass checks performed on the CSV files. It is not yet a conclusion about the business's reported 11% month-on-month recovery improvement.

## Dataset inventory
The supplied package contains 17 relational CSV datasets plus a README. The CSVs contain **639,185 rows in total including the data dictionary** (639,042 rows excluding the data dictionary).

## Coverage limitation
Most event tables run from **1 January 2026 through 8 August 2026**. The calls table begins on **29 December 2025** and runs through **12 August 2026**. Account opening dates range from 1 January 2024 to 30 November 2025. The supplied event history therefore does not support a full 12-month month-on-month reconstruction on its own. This limitation must be disclosed in the executive memo.

## First-pass quality findings
- `borrowers.csv`: 600 exact duplicate rows; 1,509 missing cells.
- `calls.csv`: 1,271 exact duplicate rows; 1,827 missing cells.
- `payments.csv`: 486 exact duplicate rows; 382 missing cells.
- `whatsapp_events.csv`: 600 exact duplicate rows.
- `accounts.csv`: 455 missing cells.
- `call_attempts.csv`: 2,400 missing cells.
- `field_visits.csv`: 250 missing cells.

These are exact row duplicates and missing-cell counts only. They do not yet quantify all business-level duplicate events or invalid relationships.

## Payment forensics — initial warning
`payments.csv` contains 25,500 rows:
- SUCCESS: 17,880
- FAILED: 3,744
- PENDING: 2,592
- REVERSED: 1,284

There are 3,745 payment references that occur more than once, covering 8,424 rows. Repeated references are **not automatically duplicates**: some repeated-reference groups span multiple accounts, amounts or statuses. Therefore, deduplicating on `payment_reference` alone would be unsafe. The next step is to inspect provider semantics, payment IDs, status transitions, reversals and account-level consistency before defining net recovered cash.

## Decisions not yet made
1. Timestamp columns do not consistently carry explicit offsets. The README warns that UTC, Asia/Kolkata and Asia/Dubai timestamps occur. We must not assume a timezone for naive timestamps without evidence.
2. A successful payment should not be treated as net recovery until reversals, duplicate ingestion and payment lifecycle semantics are reconciled.
3. Campaign attribution should not default to the latest interaction; define and test an explicit attribution window.
4. Agent identity resolution should use available stable identifiers and document ambiguous mappings.
5. The denominator for recovery rate must be fixed to a clearly defined eligible account cohort.

## Next analysis steps
1. Build source-to-golden keys and entity-resolution checks.
2. Reconcile payment events and reversals to net successful collections.
3. Normalize event timestamps using source/vendor timezone metadata where supported.
4. Build account-month and campaign-month analytical facts.
5. Calculate recovery rate using a fixed eligible-account denominator and compare like-for-like cohorts.
6. Investigate mix effects before making causal claims.
7. Only then estimate the value and ROI of an investment recommendation.
