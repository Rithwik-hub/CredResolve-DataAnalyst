# CredResolve -- Production Analytics Architecture

## System Design: Raw -> Staging -> Clean -> Golden -> Feature -> Metrics -> Dashboard

`
SOURCE SYSTEMS  ->  INGESTION LAYER  ->  RAW LAYER (append-only, partitioned)
       |
       v
STAGING LAYER  ->  CLEAN LAYER  ->  GOLDEN LAYER
(type cast,       (entity resol,     (payment_golden, account_golden,
 null handling,    dedup,             agent_golden, borrower_golden,
 dup detect)       TZ normalize,      audit columns, lineage tags)
                   reversal flag)
       |
       v
FEATURE LAYER  ->  METRICS LAYER  ->  DASHBOARD
(acct_month_facts,  contact_rate,      CEO 60-sec view
 agent_day_facts,   rpc_rate,          Recovery KPIs
 campaign_attr,     ptp_rate,          Channel mix
 channel_perf,      recovery_rate,     Agent scorecard
 cohort_facts)      rec_per_hour,      Complaint alerts
                    cost_per_recovery
`

## Data Contracts

| Layer | Primary Key | Grain | SLA |
|---|---|---|---|
| raw_payments | payment_id + _ingested_at | 1 row per ingestion event | 15 min |
| golden_payments | payment_id | 1 row per unique payment | 1 hour |
| acct_month_facts | account_id + month | 1 row per account per month | 4 hours |
| metrics_daily | metric_name + date | 1 row per metric per day | 6 hours |

## Key Design Decisions

### Incremental Processing
- All raw tables partitioned by _ingestion_date
- Golden layer rebuilt daily for 3-day lookback window (handles late events)
- Metric layer rebuilt weekly for full month (handles reversals)

### Late-Arriving Data Policy
- Events > 2 days late: quarantined, reviewed, backfilled
- Reversals: always trigger golden layer rebuild for affected month
- Historical overwrites: versioned in ccount_status_history -- use 
ecorded_at not event_at

### Data Quality Checks (Automated)
1. Row count delta > 20% from previous day => ALERT
2. Payment amount > 99th percentile => REVIEW flag
3. Null primary keys => REJECT
4. Event timestamp > 7 days in future => REJECT
5. Agent session duration > 16 hours => REVIEW flag
6. Duplicate payment_reference across accounts => QUARANTINE

## Metric Definitions

| Metric | Numerator | Denominator | Notes |
|---|---|---|---|
| Contact Rate | Accounts with >= 1 ANSWERED call | All targeted accounts | Fixed per targeting date |
| RPC Rate | Substantive dispositions | ANSWERED outbound calls | Exclude WRONG_NUMBER, VOICEMAIL |
| PTP Rate | Accounts with PTP | Targeted accounts | Date-bounded |
| PTP Kept Rate | KEPT PTPs | PTPs with matured promised_date + 7d grace | Exclude open PTPs |
| Recovery Rate | Accounts with net success payment | Eligible accounts at month start | Fixed denominator |
| Recovery/Agent-Hour | Net Rs recovered | Logged agent hours | Golden payments only |
| Channel Conversion | Accounts paid after channel touch | Accounts with channel engagement | 30-day attribution window |

## Monitoring Stack
- **Orchestration:** Apache Airflow with SLA alerts
- **Data Quality:** Great Expectations suite on each layer
- **Observability:** Grafana dashboard for pipeline health metrics
- **Alerting:** PagerDuty on golden payment count drop > 10% vs prior day
- **Lineage:** OpenLineage / Marquez for full data lineage tracking

## Backfill Strategy
- Full historical reprocessing trigger: any schema change or business rule change
- Partial backfill: reversal events, late payments (auto-triggered, 3-day window)
- Manual backfill: vendor code mapping changes, timezone corrections
