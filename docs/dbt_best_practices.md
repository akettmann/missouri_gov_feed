# dbt best practices: review of this project

Reviewed in October 2026 against dbt Labs' guides: "How we structure our dbt projects", "How we style our dbt
projects", and the testing and documentation best practices.

## Changed in this review

| Practice | Before | Now |
|---|---|---|
| Only staging models read sources | 6 intermediate/mart models read 8 raw tables directly | Every raw table read downstream has a staging model; 0 `source()` calls outside staging |
| Staging is 1:1 with a source, no joins | `stg_courtlistener__mo_cases` joined 3 sources, `stg_courtlistener__judge_disclosures` joined 2 | Split into one staging model per table; the joins live in `int_courtlistener__mo_cases` and `int_courtlistener__judge_disclosure_items` |
| Every model's grain is tested | Primary-key tests on 2 of 17 marts | a grain test (`unique` or `dbt_utils.unique_combination_of_columns`) on every mart and reporting model (#73); `fct_voluntary_disclosures` passes vacuously while its seed is empty. Two grains failed and were fixed: duplicated FEC donor totals (a real double count) and per-chamber party unity (documented as part of the grain) |
| Static mappings are seeds, not hardcoded lists | Missouri court ids hardcoded in 2 models; FEC committee-type codes undecoded | `mo_courts` and `fec_committee_types` seeds |
| Source freshness | none | `loaded_at` freshness on every always-on JSON landing; `mogov freshness` |
| Packages | none | `dbt_utils` (pinned in `package-lock.yml`); installed automatically by `mogov build`, CI and the image |
| Documentation | marts only, partly | every model, mart column and source (see `models/_docs.md`, `scripts/gen_model_docs.py`), persisted as warehouse comments |
| Repeated logic in macros | partly | `normalize_party`, `classify_outcome` (with a singular test) |

## Already in line

- Layered `staging` → `intermediate` → `marts`, with schemas and materializations set per folder in
  `dbt_project.yml`.
- Naming: `stg_<source>__<entity>`, `int_<entity>__<verb/what>`, `fct_` / `dim_`; dbt Core / dbt-duckdb (the versions pinned in `uv.lock`).
- `ref()` / `source()` everywhere; no hardcoded relation names.
- Portable SQL through `adapter.dispatch` macros (`macros/compat`), so the backend can change.
- Supported adapters: DuckDB is the only supported and tested backend (built in CI). The regex macros also have Postgres
  and Snowflake dispatches (rendered SQL pinned by `tests/test_regex_macros.py`, never run against a real
  Snowflake/Postgres); other compat macros (spatial, JSON) lack Snowflake dispatches. Which adapters to support is open
  in #121. Trino/Athena and Spark < 3.3 are not supported (no `regexp_instr`). Regex patterns are plain POSIX ERE;
  `mogov.regex_literal` handles per-adapter string escaping (Snowflake treats backslash as an escape).
- sqlfluff with the dbt templater in pre-commit and CI.
- Optional inputs gate their models with vars (`mec_direct`, `cl_case_bulk`) instead of failing.

## Deliberately not changed

- **Intermediate models are tables, not views or ephemeral.** The name-matching joins (cases, votes,
  committees) are reused by several marts, and DuckDB would otherwise recompute them for each.
- **Some staging models build on another staging model** (`stg_congress__fec_ids`, `stg_congress__terms`,
  `stg_openstates__roles`, `stg_openstates__other_names` unnest a parsed staging model). dbt's guide would
  call these `base` models. Renaming them buys little.
- **Itemized facts without a natural key** (`fct_campaign_finance`, `fct_lobbyist_gifts`,
  `fct_disclosures`, `fct_campaign_spending`, ties) have no uniqueness test. Identical rows can be genuine
  (two equal contributions on one day), so a surrogate key would hide nothing useful.
- **The Python loaders keep their own copy of the court list** (they run before dbt and can't read seeds).
  The seed's description points at them.

## Decided and done (follow-up)

| Practice | Now |
|---|---|
| One source per system | a source per upstream system (e.g. `source('fec', 'candidates')`), each in `models/staging/<system>/` with its `_<system>__sources.yml`; `identifier` keeps the raw directory names, so loaders are unchanged. Staging models are named after their source (`stg_tap_mec__*` for the TAP mirror, `stg_mec__*` for MEC direct). |
| Model contracts on the marts and reporting models | `contract: {enforced: true}` for the marts and reporting folders; every column in those models declares a `data_type`. A renamed, dropped, added or retyped column fails the build. Types are DuckDB's. |
| Exposures | `voter_frontend` (`models/reporting/_reporting.yml`) lists the tables `frontend/src/lib/exports` reads directly (marts and reporting models, exported by `mogov export`), so they show in lineage. |
| Reporting layer | `models/reporting/` (`rpt_*`, schema `reporting`), contracts enforced like the marts. Built only from marts and intermediate models. |
| Unit tests for fragile logic | dbt unit tests on fragile matching and parsing logic, e.g. House and Senate vote tokens, MEC committee attribution, CourtListener case matches, judge index names, lobbyist-gift recipients, garbled disclosure items, committee donor chains, TAP contribution layouts, municipal office titles (`_*_unit_tests.yml` beside the models they cover). They run before their model in every `mogov build`. A failing one skips the model. |

## Still open

- **CI runs `dbt parse`, not the unit tests.** dbt unit tests read their inputs' column types from the
  warehouse, and CI has no landed data.
- Grain tests on the marts and reporting models that still lack one (#73).
