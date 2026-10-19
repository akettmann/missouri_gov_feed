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
- [ ] Decide whether the House/Senate vote-token parsing (regex in Python today) should move to dbt, landing only the extracted PDF text, per "make as few changes to the raw data as possible". The House token regex uses a lookbehind, which RE2/DuckDB can't do
- [ ] Ask MEC (helpdesk@mec.mo.gov) whether a lower pause or parallel shards are acceptable; the pause is now `MOGOV_MEC_PAUSE`
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end

## Low priority
- [x] Add metrics for the loaders (rows, duration, failures, progress gauge by loader/shard; HTTP requests, bytes, latency by host)
- [x] Build GitHub workflow to run tests, lint, etc (.github/workflows/ci.yml)
- [ ] `playwright` is a dependency but nothing imports it; drop it to slim the image?
- [ ] mec_cd3_b and mec_summary are landed but no dbt model reads them
