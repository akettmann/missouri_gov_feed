# TODO List

# High Priority
- [x] review full_run.log: every loader started and finished on all 4 shards. Found and fixed: `mo_house` shards 1-2 failed (Windows cache-rename race between shards fetching the same session zip; downloads are now single-flight with a retried rename), `wikidata` shards 1-2 failed (ran before `openstates_people` landed its CSV; now stage 2), MEC cached an empty crosswalk for 2016/2018 for 30 days (no longer cached). Expected: `courtlistener_cases` quota exhausted (0 rows; resumes next day), `dbt.placeholder` for `cl_cases` in the first build
- [x] review second_run.log: no failures. `mo_house`/`mo_senate`/`house_fd` spent 3-10 min per shard re-parsing cached PDFs; PDF text is now cached by content (`data/cache/pdftext/`)
- [x] review full_run2.log / second_run2.log: full run 1h00m, quick re-run 9.4 min (was 20.7 min; PDF-text cache works, slowest loader is now `mo_house` shard 3 redoing its failed work). Found and fixed: `mo_house` shard 3 failed with `PermissionError` creating a single-flight lock file (Windows reports a pending delete that way; now treated as "lock held"), DuckDB's terminal progress bar interleaved with the logs (disabled per connection via `db.connect`), MEC's election search only offers 2020+ so 2016/2018 warned every run (default years now 2020+, unoffered years skipped). Expected: `courtlistener_cases` quota, `dbt.placeholder` for stage-2 tables in the first build, `census_tiger.not_a_zip` for the unpublished TIGER2026 SLDL
- [ ] Re-run `uv run mogov run --shards 4` once more to confirm the lock fix (no `loader.failed`) and that no progress bars appear in the log

## Frontend support (see FRONTEND_TODO.md)
### dbt
- [x] Add a `dbt/models/reporting/` layer (`rpt_*`, portable SQL, enforced contracts like the marts) shaped for the frontend pages
- [x] `rpt_indicator_peers`: each bias indicator per official alongside chamber colleagues' values and party medians
- [x] `rpt_party_breaks`: party-line votes where the official voted against their party's majority (party majorities extracted to `int_votes__party_positions`, now counted over every member who voted)
- [x] `rpt_donor_rollup`: donations received per official by donor organization, donor class (PAC vs individual), year/cycle; keeps `match_confidence`
- [x] `rpt_gift_rollup`: lobbyist gifts per official by principal, category and year (with `match_confidence`)
- [x] dbt `exposure` for the frontend (`voter_frontend` in `models/reporting/_reporting.yml`)
- [x] Decide how ACU is presented: ACU dropped (see Low priority)

### Loaders
- [x] `census_tiger`: district, county and place boundaries -> `dim_district`, `fct_official_districts` (legislators, U.S. House, circuit judges via the Official Manual's county->circuit table, mayors)
- [ ] `fct_official_districts`: map Courts of Appeals districts and federal district courts (E.D./W.D. Mo.) to counties; 7 state judges have no circuit in `dim_official`
- [x] Bill subjects/sponsors: from the MO House bill XML already landed -> `fct_bills`, `fct_bill_subjects`, `fct_bill_sponsors`, `fct_vote_bills` (House votes linked exactly; Senate votes on House bills via the journal's measure)
- [ ] Bill subjects before the 2024 sessions and Senate bills (SB/SJR): the House XML has neither. Candidate source: Open States bills API (needs a key) or senate.mo.gov bill pages
- [x] ~~Balancing ideology scorecard loader~~ (not needed: ACU dropped)

### Later (interest vs. vote overlap)
- [ ] Seed mapping donor organizations / lobbyist principals to industries or subjects (can target the House subject index terms in `fct_bill_subjects`)
- [ ] `rpt_interest_vote_overlap`: votes on bills whose subject matches an industry that funded or gifted the official (co-occurrence, not causation)

## Low priority
- [x] Fetch salaries for the officials: `mo_employee_pay` loader (data.mo.gov state payroll) -> `fct_salaries` (state officials, 2017+)
- [ ] Salaries for federal officials (Congress, federal judges): fixed by statute; a seed of yearly pay tables would cover them
- [x] when running `uv run mogov run` execute sources that are across different services concurrently (`--workers`; loaders grouped by service)
- [ ] Listing of companies that operate in the official's jurisdiction, highlight which ones have donated. Needs a decision on the source: the MO Secretary of State business search has no bulk export; Census County Business Patterns has counts but no names
- [x] Document "wipe and rebuild from scratch" in docs/environment.md
- [x] Drop ACU source
- [x] add computed attendance %: `rpt_attendance` per official, chamber and session, with the chamber-wide rate

## Future
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end (for now the pipeline runs and writes locally)
- [ ] Sunshine Law (RSMo 610) requests for Missouri personal financial disclosures (PFDs), which are not published online: officials' and candidates' from MEC (helpdesk@mec.mo.gov, 800-392-8660), judges' from the Clerk of the Missouri Supreme Court. Once copies arrive, add them through a seed or a local-folder loader
