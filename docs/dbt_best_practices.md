# dbt best practices: review of this project

Reviewed in October 2026 against dbt Labs' guides: "How we structure our dbt projects", "How we style our dbt
projects", and the testing and documentation best practices.

## Changed in this review

| Practice | Before | Now |
|---|---|---|
| Only staging models read sources | 6 intermediate/mart models read 8 raw tables directly | Every raw table read downstream has a staging model; 0 `source()` calls outside staging |
| Staging is 1:1 with a source, no joins | `stg_courtlistener__mo_cases` joined 3 sources, `stg_courtlistener__judge_disclosures` joined 2 | Split into one staging model per table; the joins live in `int_courtlistener__mo_cases` and `int_courtlistener__judge_disclosure_items` |
| Every model's grain is tested | Primary-key tests on 2 of 17 marts | `dbt_utils.unique_combination_of_columns` on every mart with a natural key (10). Two grains failed and were fixed: duplicated FEC donor totals (a real double count) and per-chamber party unity (documented as part of the grain) |
| Static mappings are seeds, not hardcoded lists | Missouri court ids hardcoded in 2 models; FEC committee-type codes undecoded | `mo_courts` and `fec_committee_types` seeds |
| Source freshness | none | `loaded_at` freshness on the 15 always-on JSON landings; `mogov freshness` |
| Packages | none | `dbt_utils` (pinned in `package-lock.yml`); installed automatically by `mogov build`, CI and the image |
| Documentation | marts only, partly | every model, mart column and source (see `models/_docs.md`, `scripts/gen_model_docs.py`), persisted as warehouse comments |
| Repeated logic in macros | partly | `normalize_party`, `classify_outcome` (with a singular test) |

## Already in line

- Layered `staging` → `intermediate` → `marts`, with schemas and materializations set per folder in
  `dbt_project.yml`.
- Naming: `stg_<source>__<entity>`, `int_<entity>__<verb/what>`, `fct_` / `dim_`.
- `ref()` / `source()` everywhere; no hardcoded relation names.
- Portable SQL through `adapter.dispatch` macros (`macros/compat`), so the backend can change.
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

## Open questions (in TODO.md)

1. **One source per system.** Everything is one `raw` source today (`source('raw', 'fec_candidates')`).
   dbt recommends one source per system (`source('fec', 'candidates')`), which gives clearer lineage and
   lets freshness and descriptions be set per system. The cost is about 60 renamed references.
2. **Model contracts on the marts.** `contract: {enforced: true}` with column `data_type`s would make the
   marts a stable interface for the frontend: a build fails if a column's name or type changes. It
   needs a type declared for all ~200 mart columns.
3. **Unit tests for the matching logic.** dbt unit tests (`unit_tests:` with fixture rows) suit the
   fragile name matching: House vote tokens in `int_mo_house__votes` and committee attribution in
   `int_mec__official_committees`.
4. **Exposures**, once the frontend exists, so its dependencies on marts show in lineage.
