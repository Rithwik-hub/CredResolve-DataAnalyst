-- CredResolve: initial staging and payment-forensics SQL
-- Run after loading data/*.csv into raw_* tables.
-- IMPORTANT: payment_reference alone is NOT a safe deduplication key.
-- First inspect duplicate groups; retain raw records for auditability.

-- 1) Exact duplicate payment rows
SELECT payment_id, account_id, borrower_id, event_at, payment_reference,
       amount, payment_status, payment_method, provider_id, COUNT(*) AS copies
FROM raw_payments
GROUP BY payment_id, account_id, borrower_id, event_at, payment_reference,
         amount, payment_status, payment_method, provider_id
HAVING COUNT(*) > 1;

-- 2) Repeated payment references: investigate account/status/amount variation
SELECT payment_reference,
       COUNT(*) AS row_count,
       COUNT(DISTINCT account_id) AS account_count,
       COUNT(DISTINCT amount) AS amount_count,
       COUNT(DISTINCT payment_status) AS status_count,
       SUM(amount) AS raw_amount_sum
FROM raw_payments
GROUP BY payment_reference
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- 3) Candidate successful payments only; not yet a final golden metric.
-- Business rules must determine treatment of reversals, retries and late events.
SELECT *
FROM raw_payments
WHERE UPPER(TRIM(payment_status)) = 'SUCCESS';

-- 4) Monthly successful payment amount using event timestamp as currently supplied.
-- Timestamp timezone normalization remains a required validation step.
SELECT DATE_TRUNC('month', CAST(event_at AS timestamp)) AS event_month,
       COUNT(*) AS success_rows,
       SUM(amount) AS gross_success_amount
FROM raw_payments
WHERE UPPER(TRIM(payment_status)) = 'SUCCESS'
GROUP BY 1
ORDER BY 1;
