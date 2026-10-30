# CredResolve Collections Analytics
## Executive Memo — Data Analyst Assignment Submission

**To:** CredResolve Hiring Team
**From:** Candidate
**Date:** 31 October 2026
**Subject:** Collections Analytics Investigation — Key Findings and Recommendations

---

## 1. Situation and Scope

CredResolve provided a synthetic collections dataset of 18 relational tables (~639k rows)
covering borrowers, accounts, agents, calls, payments, WhatsApp/SMS events, field visits,
promises-to-pay, and complaints. The stated scope was ~12 months of data. The investigation
revealed the event window runs from January to August 2026 (~7.5 months), with August 2026
being a partial month (8 days only). All findings are scoped to this window.

---

## 2. Portfolio Snapshot (As-of August 2026)

| Metric | Value |
|---|---|
| Total portfolio outstanding | Rs 1,048.9 Cr |
| Net recovery (Jan–Jul 2026, golden layer) | Rs 129.1 Cr |
| Portfolio recovery rate (eligible accounts) | 43.8% |
| Total complaints filed | 8,000 |
| Critical severity complaints | 1,968 (24.6%) |

---

## 3. The 11% Month-on-Month Claim — Verdict

**The data does not support a consistent 11% MoM improvement in net recovery.**

- Average MoM change (Jan–Jul 2026): **+0.3%** (essentially flat)
- Monthly net recovery ranged from Rs 16.8 Cr (Aug partial) to Rs 19.3 Cr
- Linear trend p-value: not statistically significant at p<0.05
- The claim may reflect a specific one-month spike, a different denominator, or
  an uncleaned figure that includes reversed/duplicate payments

**Three caveats prevent finalising this verdict:**
1. Timezone-naive timestamps may assign payments to wrong months
2. The eligible-account denominator may have changed month-to-month in the original claim
3. Mix effects (easier LOW-risk accounts growing) could mask operational trends

---

## 4. Channel Effectiveness

| Channel | Engaged Accounts | Paid Accounts | Conversion |
|---|---|---|---|
| Phone (Answered calls) | ~18,146 | Proportional | ~20% answer rate |
| WhatsApp (Payment Click) | ~10,180 | High intent | Strongest signal |
| SMS (Clicked) | ~11,139 | Moderate | Broad reach |
| Field Visit (PTP/Paid) | ~25,000 | ~8,280 | ~33% PTP conversion |

**WhatsApp payment-click is the highest-intent signal.** Accounts that click a payment link
show the strongest downstream payment correlation. This channel should be prioritised.

---

## 5. Promise-to-Pay Quality

| Status | Share |
|---|---|
| BROKEN | 25.3% |
| CANCELLED | 25.2% |
| KEPT | 24.9% |
| OPEN | 24.6% |

Only ~25% of PTPs are kept. The ~25% broken PTP rate represents predictable cash-flow
leakage that can be reduced with automated follow-ups at the 24h and 48h mark post-PTP.

---

## 6. Complaint Risk

The complaint profile reveals **significant regulatory exposure**:
- 1,126 HARASSMENT complaints (~14% of all complaints)
- 1,152 DND violations (~14%)
- 1,155 PRIVACY complaints (~14%)
- 1,968 CRITICAL severity complaints (24.6% of total)

These figures indicate systemic agent behaviour issues. Without immediate remediation,
the firm faces regulatory action risk from the RBI and TRAI.

---

## 7. Data Quality Findings

| Issue | Tables Affected | Risk |
|---|---|---|
| Exact duplicate rows | borrowers (600), calls (1,271), payments (486), whatsapp (600) | Double-counting |
| Repeated payment_reference (3,745 groups) | payments | Overstated recovery |
| Mixed timezones (UTC/IST/GST) | calls, accounts, agent_sessions | Wrong-month allocation |
| Missing cells | call_attempts (2,400), borrowers (1,509), calls (1,827) | Analysis gaps |
| Legacy disposition codes | call_dispositions | PTP under-identification |

**Critical finding:** Using raw SUCCESS count as the recovery metric would overstate net
recovery by including reversed payments and duplicate ingestion events.

---

## 8. Recommendations

### Immediate (0-30 days)
1. **Compliance training** for all calling agents — focus on DND, harassment protocols
2. **Data dedup pipeline** — implement the golden layer approach described in the notebook
3. **Timezone normalisation** — tag all events with canonical IST timestamps at ingestion

### Near-term (30-90 days)
4. **WhatsApp-first outreach** — shift high-DPD accounts to WhatsApp primary, call secondary
5. **PTP automation** — 24h and 48h automated WhatsApp/SMS reminders after every PTP
6. **Fixed-denominator reporting** — lock the eligible cohort at month start for fair MoM comparison

### Strategic (90-180 days)
7. **A/B test:** WhatsApp-first + PTP-automation cohort vs. call-first control
   - Stratify by: risk segment, DPD bucket, loan type, outstanding quintile
   - Primary KPI: 60-day payment rate | Secondary: cost per recovered account
8. **Risk-stratified channel routing:**
   - HIGH/NPA segments => Field visits (high engagement value justifies cost)
   - MEDIUM => SMS + WhatsApp
   - LOW => WhatsApp self-serve only

---

## 9. Production Analytics Architecture (Recommended)

`
Raw CSV / API Feeds
        |
        v
[Ingestion Layer] -- timezone tagging, schema validation, dedup fingerprint
        |
        v
[Raw Layer] -- immutable, append-only; all original rows preserved
        |
        v
[Golden Layer] -- entity-resolved, timezone-normalised, deduped, reversal-adjusted
        |
        v
[Analytical Layer] -- account-month facts, agent-day facts, campaign attribution facts
        |
        v
[BI / Dashboard] -- recovery rate, channel KPIs, agent scorecards, complaint dashboard
        |
        v
[Alerting] -- PTP broken spike, complaint volume surge, daily recovery shortfall
`

---

## 10. Key Limitations and Disclosures

1. Event window is ~7.5 months (Jan-Aug 2026), not 12 months as stated. Aug partial.
2. Timezone-naive timestamps create month-boundary uncertainty for ~40% of event tables.
3. The 11% MoM claim cannot be confirmed or refuted without a fixed eligible-account
   denominator and timezone-corrected event timestamps.
4. This analysis uses a synthetic dataset; real-world patterns may differ.

---

*Submitted as part of the CredResolve Data Analyst assignment. Full analysis, charts, and
reproducible pipeline are available in the GitHub repository.*
