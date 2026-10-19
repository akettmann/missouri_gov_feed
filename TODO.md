# TODO List

## High priority
- [x] Unify the state roll-call window and default it to 10 years: `MOGOV_LOOKBACK_YEARS` (default 10) replaces MOGOV_HOUSE_SESSIONS / MOGOV_SENATE_YEARS; House extraordinary sessions are discovered
- [x] Add progress logging to the loaders (`loader.progress`, every MOGOV_PROGRESS_SECONDS)
- [x] Review loaders against the guidelines in CLAUDE.md: streaming JsonSink, `--shards`/`--shard` + process pool, Cloud Run task env, JSON logs with severity, SIGTERM handling, Dockerfile
- [x] Review the MEC loader speed: the crosswalk (~9 of ~13 min) was never cached, and lost the ASP.NET view state after the first export of each year (non-November elections landed site-footer junk). Now cached, view state fixed, form reused across years. The remaining cost is the 3 s pause per request (MEC answers in <1 s)

## Medium priority
- [x] Add diagrams using PlantUML that describe the data model (docs/diagrams/data_model.puml, lineage.puml, pipeline.puml)
- [x] Add diagrams using PlantUML that describe each source and loader's uniqueness (docs/diagrams/sources/)
- [x] Build case history from CourtListener's quarterly bulk files (`courtlistener_case_bulk` + int_courtlistener__bulk_case_matches); the API loader stays for top-ups
- [x] House/Senate vote-token parsing stays in the Python loaders: turning the PDF into rows of data is an acceptable transformation
- [x] Update DBT with detailed definitions/contexts: every mart column documented (_marts.yml, shared doc blocks in models/_docs.md), staging/intermediate model descriptions generated from their SQL headers (scripts/gen_model_docs.py), every raw source described; mart docs persist as table/column comments in DuckDB
- [ ] Ask MEC (helpdesk@mec.mo.gov) whether a lower pause or parallel shards are acceptable; the pause is `MOGOV_MEC_PAUSE` (a cold run is ~10-11 min at 3 s, ~4-5 min at 1 s)
- [ ] Normalize `party` ("Democratic" and "Democrat" both occur in dim_official)
- [ ] Decode FEC committee-type codes in fct_campaign_finance.counterparty_type (raw N/Q/X/Y/H/S/V/W today)
- [ ] fct_case_history.outcome is mostly CourtListener's verbatim disposition; map it to a fixed vocabulary (affirmed / reversed / remanded / dismissed / mixed ...)

## Low priority
- [x] Add metrics for the loaders (rows, duration, failures, progress gauge by loader/shard; HTTP requests, bytes, latency by host)
- [x] Build GitHub workflow to run tests, lint, etc (.github/workflows/ci.yml)
- [x] Drop the unused `playwright` dependency
- [ ] Frontend candidates, landed but not modeled: `mec_cd3_b` (itemized committee spending over $100: payee, purpose, amount - "how did their committee spend its money") and `mec_summary` (per-report cover totals: raised, spent, money on hand, debt - "raised $X, spent $Y, $Z in the bank")

## Future
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end (for now the pipeline runs and writes locally)
