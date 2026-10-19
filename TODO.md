# TODO List

## Frontend support (see FRONTEND_TODO.md)
### dbt
- [ ] Add a `dbt/models/reporting/` layer (`rpt_*`, portable SQL, enforced contracts like the marts) shaped for the frontend pages
- [ ] `rpt_indicator_peers`: each bias indicator per official alongside chamber colleagues' values and party medians
- [ ] `rpt_party_breaks`: party-line votes where the official voted against their party's majority (reuse the party-unity logic in `fct_bias_indicators`; consider extracting it to an intermediate model)
- [ ] `rpt_donor_rollup`: donations received per official by counterparty organization, counterparty type (PAC vs individual), cycle/year; keep `match_confidence` so the UI can flag/hide medium matches
- [ ] `rpt_gift_rollup`: lobbyist gifts per official by principal, category and year (with `match_confidence`)
- [ ] dbt `exposure` for the frontend so its mart/reporting dependencies show in lineage (docs/dbt_best_practices.md)
- [ ] Decide how ACU is presented: add a progressive-leaning scorecard source for balance, or keep ACU out of headline indicators

### Loaders
- [ ] `census_tiger`: Missouri state legislative (SLDU/SLDL) and congressional district boundaries, plus county boundaries (judicial circuits) and places (mayors); dbt model joining districts to `dim_official`
- [ ] Bill subjects/sponsors loader (Open States bills API or MO House bill pages) so votes can be grouped by topic
- [ ] Balancing ideology scorecard loader (if chosen above)

### Later (interest vs. vote overlap)
- [ ] Seed mapping donor organizations / lobbyist principals to industries or subjects
- [ ] `rpt_interest_vote_overlap`: votes on bills whose subject matches an industry that funded or gifted the official (co-occurrence, not causation)

## Low priority
- [ ] Document "wipe and rebuild from scratch" in docs/environment.md: what to delete (data/raw, mogov.duckdb, exports; optionally data/cache), `mogov run --shards 4`, verification (`mogov build`, `mogov freshness`), and expected time with vs. without the cache; Docker variant

## Future
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end (for now the pipeline runs and writes locally)
