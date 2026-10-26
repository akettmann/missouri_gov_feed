# Tools
## pre-commit
Add reasonable pre-commit hooks for linting and formatting

## Python
Package management: uv
Workspace management: uv
testing: Pytest
linting: Ruff
logging: Structlog
metrics: Opentelemetry
XML parsing: an XML parser (lxml), never regex or `mogov.xmljson`
## ETL
DBT Core
DuckDB backend
Use compatible constructs from DBT to make switching backends possible
linting: SqlFluff
Optional inputs are gated by vars (`mec_direct`, `cl_case_bulk`): build with `mogov build`, or pass the vars when running bare `dbt` (the hook also runs for bare `dbt snapshot` / `dbt source freshness`; it fails the run if raw data exists but the var is off; opt out with `skip_optional_raw_check`)
if useful, add dbt-utils and dbt-expectations to the DBT project
Follow DBT's best practices https://docs.getdbt.com/best-practices?version=2
Where possible, build tests that serve as "sanity checks". Example: We have never seen 200 roll calls in a day before, no campaign has received 1 trillion dollars
## Loader processes
Loaders are processes that fetch raw data and write it to our raw storage.
They will be:
* Python
* Idempotent
* Streaming
* Make as few changes to the raw data as possible when writing it to the raw storage
* XML sources: store each raw XML file unchanged in raw storage, and parse it (with an XML parser) into rows of the entities it contains, e.g. a document listing laws emits one row per law with that law's fields/attributes as columns
* emit progress when reasonably knowable (don't add a lot of extra work here. Ask if you are unsure.)
* be shardable, can spawn workers in parallel that split up the work independently (ensure the split mechanism is idempotent). Ideally use options `--shards` to indicate the max number of shards, and `--shard` to indicate that process's shard. If `--shards` is provided and `--shard` is not provided, the process should run a processpool of `--shards` number of workers
  * If it would require every worker to download the same file, don't use multiple workers until you have downloaded the file once, if the file then needs to be split, we can use multiple processes on that machine
* Ready to run in the Google Cloud Run Jobs runtime (Refer to the Google cloud container contract cloud_run_container_contract.md)
## Documentation
Diagrams/flowcharts are written in PlantUML
Maintain step by step documentation of:
* How to build an environment from scratch
* How to keep an environment's data in sync
* a Per source section that describes the source in brief. Also it will include details of any quirks identified for that source
* a summary of our sources and what types of data they provide
## Issue Tracking
Issues live in GitHub issues on `akettmann/missouri_gov_feed`, managed with the `gh` CLI (`gh issue create`, `gh issue list`).
* If you find a problem while working, if it is not blocking your progress, file it as an issue instead of fixing it in passing.
* Reference issues in commits and PRs (`Fixes #12`) so they close when the work merges.
* Use only the labels below. If a new one seems needed (e.g. a new source), ask before creating it, and add it to this list.
* Every issue gets exactly one priority label, at least one area label, and a `source:` label for each source it involves.

Acceptable labels:
* Priority: `priority: high`, `priority: medium`, `priority: low`
* Area: `Frontend`, `Ingest` (Python loaders), `Transformation (DBT)`, `documentation`
* Kind: `bug` (something is wrong; omit for new work)
* Status: `needs-user` (blocked on an action or decision only the maintainer can take)
* Source, one per loader in `src/mogov/loaders` (see docs/sources.md): `source: mo_house`, `source: mo_senate`,
  `source: mo_senate_topics`, `source: mec`, `source: tap_mec`, `source: fec`, `source: voteview`,
  `source: house_fd`, `source: senate_efd`, `source: courtlistener_bulk`, `source: courtlistener_case_bulk`,
  `source: courtlistener_cases`, `source: bluebook`, `source: openstates_people`, `source: congress_legislators`,
  `source: fjc_judges`, `source: wikidata`, `source: shor_mccarty`, `source: census_tiger`, `source: census_zcta`,
  `source: mo_employee_pay`, `source: epa_frs`, `source: mo_auditor`, `source: mo_revisor`
* Candidate sources (not loaded yet): `source: legiscan`, `source: followthemoney`, `source: osha_ita`,
  `source: mo_sos_business`, `source: mo_state_expenditures`, `source: govinfo_billstatus`, `source: house_sod`,
  `source: house_cpf`, `source: mo_sos_elections`, `source: census_acs`,
  `source: uscourts_caseload`, `source: mo_sos_rules`. When a candidate gets a loader, keep the label and update its description.

Frontend issues follow the rules in docs/frontend_principles.md.
