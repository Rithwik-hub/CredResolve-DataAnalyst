-- ============================================================
-- CredResolve Collections Analytics -- SQL Repository
-- Production-Quality SQL for all 5 Parts of the Assignment
-- ============================================================

-- ============================================================
-- PART 1: GOLDEN DATASET PIPELINE
-- ============================================================

-- Step 1A: Stage borrowers -- deduplicate on borrower_id, keep latest
CREATE OR REPLACE VIEW stg_borrowers AS
SELECT *,
       ROW_NUMBER() OVER (PARTITION BY borrower_id ORDER BY updated_at DESC) AS rn
FROM raw_borrowers;

CREATE OR REPLACE VIEW golden_borrowers AS
SELECT borrower_id, name, phone, email, city, state, created_at, updated_at
FROM stg_borrowers WHERE rn = 1;

-- Step 1B: Stage accounts -- keep latest schema_version per account
CREATE OR REPLACE VIEW golden_accounts AS
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY opened_at DESC) AS rn
    FROM raw_accounts
) t WHERE rn = 1;

-- Step 1C: Stage agents -- resolve multiple identifiers
-- Agents may appear under different agent_id but same employee_code
CREATE OR REPLACE VIEW golden_agents AS
SELECT
    a.agent_id,
    a.employee_code,
    a.agent_name,
    a.vendor_id,
    a.team,
    a.status,
    a.joined_at,
    a.updated_at,
    ROW_NUMBER() OVER (PARTITION BY a.employee_code ORDER BY a.joined_at ASC) AS tenure_rank
FROM raw_agents a;

-- Step 1D: Payments golden layer
-- CRITICAL: payment_reference is NOT a safe dedup key alone
-- Strategy: remove byte-identical rows, flag reversal groups, exclude from net recovery

CREATE OR REPLACE VIEW stg_payments AS
SELECT *,
       COUNT(*) OVER (PARTITION BY payment_id, account_id, borrower_id, event_at,
                      payment_reference, amount, payment_status, payment_method, provider_id)
           AS exact_copy_count
FROM raw_payments;

-- Reversal-flagged references (any row in group = REVERSED tags entire group)
CREATE OR REPLACE VIEW reversal_refs AS
SELECT DISTINCT payment_reference
FROM raw_payments
WHERE UPPER(TRIM(payment_status)) = 'REVERSED';

-- Golden successful payments (net recovery)
CREATE OR REPLACE VIEW golden_payments AS
SELECT
    p.payment_id,
    p.account_id,
    p.borrower_id,
    p.event_at,
    p.payment_reference,
    p.amount,
    p.payment_status,
    p.payment_method,
    p.provider_id,
    'SUCCESS_NO_REVERSAL' AS golden_flag
FROM stg_payments p
WHERE p.exact_copy_count = 1  -- remove byte duplicates
  AND UPPER(TRIM(p.payment_status)) = 'SUCCESS'
  AND p.payment_reference NOT IN (SELECT payment_reference FROM reversal_refs)
QUALIFY ROW_NUMBER() OVER (PARTITION BY p.payment_id ORDER BY p.event_at DESC) = 1;

-- ============================================================
-- PART 2: DATA FORENSICS
-- ============================================================

-- A. Duplicate payment detection
SELECT
    payment_reference,
    COUNT(*)                        AS row_count,
    COUNT(DISTINCT payment_id)      AS distinct_payment_ids,
    COUNT(DISTINCT account_id)      AS distinct_accounts,
    COUNT(DISTINCT amount)          AS distinct_amounts,
    COUNT(DISTINCT payment_status)  AS distinct_statuses,
    COUNT(DISTINCT provider_id)     AS distinct_providers,
    SUM(amount)                     AS raw_amount_sum,
    MIN(event_at)                   AS first_event,
    MAX(event_at)                   AS last_event,
    DATEDIFF('second', MIN(event_at), MAX(event_at)) AS seconds_span
FROM raw_payments
GROUP BY payment_reference
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- B. Attribution error check: payments vs last campaign interaction
-- Flag payments where event_at precedes the attributed campaign start
SELECT
    p.payment_id,
    p.account_id,
    p.event_at AS payment_time,
    dt.campaign_id,
    dt.target_date AS campaign_date,
    c.start_at AS campaign_start,
    CASE WHEN p.event_at < c.start_at THEN 'ATTRIBUTION_ERROR' ELSE 'OK' END AS attribution_flag
FROM golden_payments p
LEFT JOIN daily_targeting dt ON dt.account_id = p.account_id
LEFT JOIN campaigns c        ON c.campaign_id = dt.campaign_id
WHERE p.event_at < c.start_at;

-- C. Timezone audit: calls being classified into wrong hour
SELECT
    vendor_id,
    timezone,
    COUNT(*)                                AS call_count,
    AVG(duration_sec)                       AS avg_duration,
    MIN(event_at)                           AS first_call,
    MAX(event_at)                           AS last_call
FROM raw_calls
GROUP BY vendor_id, timezone
ORDER BY call_count DESC;

-- Calls in potentially wrong business hours (midnight-6am IST = UTC 18:30-00:30)
SELECT
    c.call_id,
    c.event_at,
    c.timezone,
    EXTRACT(HOUR FROM c.event_at)           AS raw_hour,
    v.timezone                              AS vendor_timezone
FROM raw_calls c
LEFT JOIN vendor_telephony v ON v.vendor_id = c.vendor_id
WHERE EXTRACT(HOUR FROM c.event_at) BETWEEN 22 AND 6  -- likely wrong-timezone calls
LIMIT 100;

-- D. Vendor/disposition code changes over time
SELECT
    CAST(event_at AS DATE)              AS event_date,
    disposition_version,
    COUNT(DISTINCT disposition_code)    AS distinct_codes,
    COUNT(*)                            AS total_dispositions
FROM raw_call_dispositions
GROUP BY event_date, disposition_version
ORDER BY event_date;

-- Legacy vs current PTP codes (both should be treated as PTP intent)
SELECT
    disposition_code,
    disposition_version,
    COUNT(*) AS occurrences,
    MIN(event_at) AS first_seen,
    MAX(event_at) AS last_seen
FROM raw_call_dispositions
WHERE disposition_code IN ('PTP','PROMISE_TO_PAY','PTY','P2P')
GROUP BY disposition_code, disposition_version;

-- E. Agent identity resolution: same agent under multiple IDs
SELECT
    agent_name,
    COUNT(DISTINCT agent_id)        AS id_count,
    COUNT(DISTINCT employee_code)   AS emp_code_count,
    COUNT(DISTINCT vendor_id)       AS vendor_count,
    MIN(joined_at)                  AS first_joined,
    MAX(joined_at)                  AS last_joined
FROM raw_agents
GROUP BY agent_name
HAVING COUNT(DISTINCT agent_id) > 1
ORDER BY id_count DESC;

-- F. Portfolio mix shift: DPD distribution over time
SELECT
    DATE_TRUNC('month', a.opened_at)    AS cohort_month,
    a.risk_segment,
    a.loan_type,
    COUNT(*)                            AS account_count,
    AVG(a.dpd)                          AS avg_dpd,
    AVG(a.outstanding_amount)           AS avg_outstanding,
    AVG(a.principal_amount)             AS avg_principal
FROM raw_accounts a
GROUP BY cohort_month, risk_segment, loan_type
ORDER BY cohort_month, risk_segment;

-- G. Denominator manipulation: accounts disappearing from active pool
-- Check if accounts move from active to closed/written-off right before measurement
SELECT
    DATE_TRUNC('month', h.event_at)     AS month,
    h.status,
    COUNT(DISTINCT h.account_id)        AS accounts_changed_status
FROM raw_account_status_history h
WHERE h.status IN ('CLOSED','WRITTENOFF','WRITEOFF','PAID')
GROUP BY month, h.status
ORDER BY month, h.status;

-- ============================================================
-- PART 3: METRIC DEFINITIONS (Correct/Challenged Definitions)
-- ============================================================

-- 3A. CONTACT RATE (correct definition)
-- Denominator = all accounts targeted in period (not just accounts called)
-- Numerator = accounts with at least one ANSWERED call
SELECT
    DATE_TRUNC('month', dt.target_date) AS month,
    COUNT(DISTINCT dt.account_id)       AS targeted_accounts,
    COUNT(DISTINCT CASE WHEN c.call_status = 'ANSWERED' THEN c.account_id END) AS contacted_accounts,
    ROUND(
        COUNT(DISTINCT CASE WHEN c.call_status = 'ANSWERED' THEN c.account_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT dt.account_id), 0), 2
    )                                   AS contact_rate_pct
FROM raw_daily_targeting dt
LEFT JOIN raw_calls c ON c.account_id = dt.account_id
    AND CAST(c.event_at AS DATE) = dt.target_date
    AND c.call_status = 'ANSWERED'
GROUP BY month ORDER BY month;

-- 3B. RPC RATE (Right Party Contact)
-- Only ANSWERED outbound calls with a substantive disposition
SELECT
    DATE_TRUNC('month', c.event_at)     AS month,
    COUNT(DISTINCT c.call_id)           AS answered_calls,
    COUNT(DISTINCT CASE WHEN d.disposition_code NOT IN ('WRONG_NUMBER','NO_CONTACT','VOICEMAIL')
                        THEN c.call_id END) AS rpc_calls,
    ROUND(
        COUNT(DISTINCT CASE WHEN d.disposition_code NOT IN ('WRONG_NUMBER','NO_CONTACT','VOICEMAIL')
                            THEN c.call_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT c.call_id), 0), 2
    )                                   AS rpc_rate_pct
FROM raw_calls c
LEFT JOIN raw_call_dispositions d ON d.call_id = c.call_id
WHERE c.call_status = 'ANSWERED' AND c.direction = 'OUTBOUND'
GROUP BY month ORDER BY month;

-- 3C. PTP RATE (against targeted accounts, not just answered calls)
SELECT
    DATE_TRUNC('month', dt.target_date) AS month,
    COUNT(DISTINCT dt.account_id)       AS targeted_accounts,
    COUNT(DISTINCT p.account_id)        AS ptp_accounts,
    ROUND(
        COUNT(DISTINCT p.account_id) * 100.0
        / NULLIF(COUNT(DISTINCT dt.account_id), 0), 2
    )                                   AS ptp_rate_pct
FROM raw_daily_targeting dt
LEFT JOIN raw_promises_to_pay p ON p.account_id = dt.account_id
    AND DATE_TRUNC('month', p.event_at) = DATE_TRUNC('month', dt.target_date)
GROUP BY month ORDER BY month;

-- 3D. PTP KEPT RATE (only mature PTPs: promised_date + 7 days grace period has passed)
SELECT
    DATE_TRUNC('month', ptp.event_at)   AS ptp_month,
    COUNT(*)                            AS total_ptps,
    SUM(CASE WHEN ptp.status = 'KEPT' THEN 1 ELSE 0 END)   AS kept,
    SUM(CASE WHEN ptp.status = 'BROKEN' THEN 1 ELSE 0 END) AS broken,
    ROUND(
        SUM(CASE WHEN ptp.status = 'KEPT' THEN 1 ELSE 0 END)
        * 100.0 / NULLIF(COUNT(*), 0), 2
    )                                   AS kept_rate_pct
FROM raw_promises_to_pay ptp
WHERE ptp.promised_date < CURRENT_DATE - INTERVAL '7 days'  -- exclude immature PTPs
GROUP BY ptp_month ORDER BY ptp_month;

-- 3E. RECOVERY RATE (fixed denominator = eligible accounts at period start)
-- Eligible = accounts with outstanding_amount > 0, not PAID, open at month start
WITH eligible AS (
    SELECT
        account_id,
        DATE_TRUNC('month', opened_at) AS cohort_month
    FROM raw_accounts
    WHERE status != 'PAID'
      AND outstanding_amount > 0
),
paid_by_month AS (
    SELECT DISTINCT
        p.account_id,
        DATE_TRUNC('month', p.event_at) AS payment_month
    FROM golden_payments p
)
SELECT
    e.cohort_month,
    COUNT(DISTINCT e.account_id)        AS eligible_accounts,
    COUNT(DISTINCT pbm.account_id)      AS recovered_accounts,
    ROUND(
        COUNT(DISTINCT pbm.account_id) * 100.0
        / NULLIF(COUNT(DISTINCT e.account_id), 0), 2
    )                                   AS recovery_rate_pct
FROM eligible e
LEFT JOIN paid_by_month pbm ON pbm.account_id = e.account_id
GROUP BY e.cohort_month ORDER BY e.cohort_month;

-- 3F. RECOVERY PER AGENT-HOUR
SELECT
    DATE_TRUNC('month', s.login_at)     AS month,
    s.agent_id,
    SUM(EXTRACT(EPOCH FROM (s.logout_at - s.login_at)) / 3600.0) AS logged_hours,
    SUM(p.amount)                       AS recovered_amount,
    ROUND(
        SUM(p.amount)
        / NULLIF(SUM(EXTRACT(EPOCH FROM (s.logout_at - s.login_at)) / 3600.0), 0), 2
    )                                   AS recovery_per_hour
FROM raw_agent_sessions s
LEFT JOIN raw_calls c ON c.agent_id = s.agent_id
    AND c.event_at BETWEEN s.login_at AND s.logout_at
LEFT JOIN golden_payments p ON p.account_id = c.account_id
    AND DATE_TRUNC('month', p.event_at) = DATE_TRUNC('month', s.login_at)
GROUP BY month, s.agent_id
ORDER BY month, recovery_per_hour DESC;

-- 3G. CHANNEL CONVERSION (WhatsApp payment-click to actual payment)
SELECT
    DATE_TRUNC('month', w.event_at)     AS month,
    w.event_type,
    COUNT(DISTINCT w.account_id)        AS accounts,
    COUNT(DISTINCT p.account_id)        AS accounts_that_paid,
    ROUND(
        COUNT(DISTINCT p.account_id) * 100.0
        / NULLIF(COUNT(DISTINCT w.account_id), 0), 2
    )                                   AS conversion_pct
FROM raw_whatsapp_events w
LEFT JOIN golden_payments p ON p.account_id = w.account_id
    AND DATE_TRUNC('month', p.event_at) = DATE_TRUNC('month', w.event_at)
GROUP BY month, event_type
ORDER BY month, event_type;

-- ============================================================
-- PART 4: STATISTICAL INVESTIGATION
-- ============================================================

-- Mix effect: Is recovery improving because portfolio is getting easier?
-- Compare DPD distribution of recovered accounts vs all eligible accounts by month
WITH monthly_recovery AS (
    SELECT
        DATE_TRUNC('month', p.event_at) AS month,
        a.risk_segment,
        a.loan_type,
        CASE
            WHEN a.dpd < 30  THEN 'DPD<30'
            WHEN a.dpd < 60  THEN 'DPD30-60'
            WHEN a.dpd < 90  THEN 'DPD60-90'
            WHEN a.dpd < 180 THEN 'DPD90-180'
            ELSE 'DPD180+'
        END AS dpd_bucket,
        COUNT(DISTINCT p.account_id)    AS recovered_accounts
    FROM golden_payments p
    LEFT JOIN raw_accounts a ON a.account_id = p.account_id
    GROUP BY month, risk_segment, loan_type, dpd_bucket
),
monthly_eligible AS (
    SELECT
        risk_segment,
        loan_type,
        CASE
            WHEN dpd < 30  THEN 'DPD<30'
            WHEN dpd < 60  THEN 'DPD30-60'
            WHEN dpd < 90  THEN 'DPD60-90'
            WHEN dpd < 180 THEN 'DPD90-180'
            ELSE 'DPD180+'
        END AS dpd_bucket,
        COUNT(*)                        AS eligible_accounts
    FROM raw_accounts WHERE status != 'PAID'
    GROUP BY risk_segment, loan_type, dpd_bucket
)
SELECT
    r.month,
    r.risk_segment,
    r.dpd_bucket,
    r.recovered_accounts,
    e.eligible_accounts,
    ROUND(r.recovered_accounts * 100.0 / NULLIF(e.eligible_accounts, 0), 2) AS segment_recovery_rate
FROM monthly_recovery r
LEFT JOIN monthly_eligible e USING (risk_segment, loan_type, dpd_bucket)
ORDER BY r.month, r.risk_segment;

-- Simpson paradox check: aggregate vs within-segment trend
WITH seg_rates AS (
    SELECT
        DATE_TRUNC('month', p.event_at) AS month,
        a.risk_segment,
        COUNT(DISTINCT p.account_id)    AS recovered,
        COUNT(DISTINCT a.account_id)    AS eligible
    FROM raw_accounts a
    LEFT JOIN golden_payments p ON p.account_id = a.account_id
    WHERE a.status != 'PAID'
    GROUP BY month, risk_segment
)
SELECT
    month,
    SUM(recovered) * 100.0 / NULLIF(SUM(eligible), 0) AS aggregate_rate,
    MAX(CASE WHEN risk_segment='HIGH'   THEN recovered*100.0/NULLIF(eligible,0) END) AS high_rate,
    MAX(CASE WHEN risk_segment='MEDIUM' THEN recovered*100.0/NULLIF(eligible,0) END) AS medium_rate,
    MAX(CASE WHEN risk_segment='LOW'    THEN recovered*100.0/NULLIF(eligible,0) END) AS low_rate,
    MAX(CASE WHEN risk_segment='NPA'    THEN recovered*100.0/NULLIF(eligible,0) END) AS npa_rate
FROM seg_rates
GROUP BY month ORDER BY month;

-- Survivorship bias: accounts that exited the pool
SELECT
    DATE_TRUNC('month', h.event_at)     AS month,
    h.status,
    COUNT(DISTINCT h.account_id)        AS accounts_exited,
    AVG(a.outstanding_amount)           AS avg_outstanding_at_exit,
    AVG(a.dpd)                          AS avg_dpd_at_exit
FROM raw_account_status_history h
JOIN raw_accounts a ON a.account_id = h.account_id
WHERE h.status IN ('PAID','CLOSED','WRITTENOFF')
GROUP BY month, h.status ORDER BY month;

-- ============================================================
-- PART 5: COUNTERFACTUAL (Difference-in-Differences)
-- ============================================================

-- Identify treatment group: accounts whose targeting strategy changed midpoint
-- Proxy: accounts that appear in daily_targeting after a new campaign start
WITH campaign_midpoint AS (
    SELECT
        AVG(EXTRACT(EPOCH FROM start_at)::BIGINT)::BIGINT AS mid_epoch
    FROM campaigns
),
treatment_accounts AS (
    SELECT DISTINCT dt.account_id
    FROM daily_targeting dt
    JOIN campaigns c ON c.campaign_id = dt.campaign_id
    WHERE c.start_at > TO_TIMESTAMP((SELECT mid_epoch FROM campaign_midpoint))
),
pre_post AS (
    SELECT
        p.account_id,
        CASE WHEN p.account_id IN (SELECT account_id FROM treatment_accounts)
             THEN 'TREATMENT' ELSE 'CONTROL' END AS group_flag,
        CASE WHEN p.event_at < TO_TIMESTAMP((SELECT mid_epoch FROM campaign_midpoint))
             THEN 'PRE' ELSE 'POST' END AS period,
        SUM(p.amount) AS recovered,
        COUNT(*)      AS payment_count
    FROM golden_payments p
    GROUP BY p.account_id, group_flag, period
)
-- DiD estimator: (Treatment_POST - Treatment_PRE) - (Control_POST - Control_PRE)
SELECT
    group_flag,
    period,
    COUNT(DISTINCT account_id)  AS accounts,
    SUM(recovered)              AS total_recovered,
    AVG(recovered)              AS avg_recovered_per_account
FROM pre_post
GROUP BY group_flag, period
ORDER BY group_flag, period;

-- ============================================================
-- PART 5: PRODUCTION PIPELINE MONITORING
-- ============================================================

-- Data quality check: row counts vs previous day (anomaly detection)
SELECT
    table_name,
    load_date,
    row_count,
    LAG(row_count) OVER (PARTITION BY table_name ORDER BY load_date) AS prev_count,
    ROUND(
        (row_count - LAG(row_count) OVER (PARTITION BY table_name ORDER BY load_date))
        * 100.0 / NULLIF(LAG(row_count) OVER (PARTITION BY table_name ORDER BY load_date), 0), 2
    )                                   AS pct_change,
    CASE
        WHEN ABS((row_count - LAG(row_count) OVER (PARTITION BY table_name ORDER BY load_date))
             * 100.0 / NULLIF(LAG(row_count) OVER (PARTITION BY table_name ORDER BY load_date), 0))
             > 20 THEN 'ALERT'
        ELSE 'OK'
    END                                 AS status
FROM pipeline_row_counts
ORDER BY load_date DESC, table_name;

-- Late-arriving event detection (events arriving more than 2 days after event_at)
SELECT
    'payments'                              AS source_table,
    payment_id                              AS record_id,
    event_at,
    _ingested_at,
    DATEDIFF('day', event_at, _ingested_at) AS latency_days
FROM raw_payments
WHERE DATEDIFF('day', event_at, _ingested_at) > 2
UNION ALL
SELECT 'calls', call_id, event_at, _ingested_at,
       DATEDIFF('day', event_at, _ingested_at)
FROM raw_calls
WHERE DATEDIFF('day', event_at, _ingested_at) > 2;
