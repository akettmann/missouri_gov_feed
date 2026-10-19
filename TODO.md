# TODO List

## Medium priority
- [ ] Decode FEC committee-type codes in fct_campaign_finance.counterparty_type (raw N/Q/X/Y/H/S/V/W today)
- [ ] fct_case_history.outcome is mostly CourtListener's verbatim disposition; map it to a fixed vocabulary (affirmed / reversed / remanded / dismissed / mixed ...)

## Low priority
- [ ] Model `mec_cd3_b` (itemized committee spending over $100: payee, purpose, amount) and `mec_summary` (per-report cover totals: raised, spent, money on hand, debt) for the frontend

## Future
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end (for now the pipeline runs and writes locally)
