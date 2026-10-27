# Keeping an environment's data in sync

Every loader is idempotent. Re-running one replaces its raw parts with a fresh landing, and the HTTP
cache decides what actually goes back to the network. So "syncing" just means running the pipeline
again:

```
uv run mogov run --shards 4
```

Loaders that land files rather than rows (today `mo_house`, whose XML goes to `data/raw/mo_house_xml/` as
gzip, and `mo_house_docs`, whose PDFs go to `data/raw/mo_house_docs/` unchanged) keep the file bytes unchanged and parse them in a second step inside the same run. To change only the
parsing, re-parse the landed files without fetching: `uv run python -m mogov.parsers.mo_house`.

Existing environments: `mo_house` used to land JSON tables. Run `uv run mogov load mo_house` once before the next
`mogov build`, because the staging models now read the `mo_house_xml_*` tables, which only that load creates.
`data/raw/mo_house_bills`, `data/raw/mo_house_lists` and `data/raw/mo_house_members` are no longer read by
anything and can be deleted.

`mo_senate` now lands each vote's `Vacancies—N` count and the 2024+ "Excused from voting" lines that follow it. Run
`uv run mogov load mo_senate` once (journal PDFs and their extracted text are cached, so it takes seconds) before the
next `mogov build`. Until then `assert_senate_vacancies_parsed` fails and 2024+ recusals are missing.

Parser change (#384): `mo_house_xml_bill_witnesses` no longer holds empty `<Witness/>` rows (2,469 of 6,633) and
the always-empty `mo_house_xml_senate_act_sponsors` / `_subjects` tables are no longer written. Re-parse once
(`uv run python -m mogov.parsers.mo_house`, or a `mogov load mo_house`) to apply it; the staging models already
ignore empty witness rows, so a build before the re-parse is still correct. Delete the two stale
`data/raw/mo_house_xml_senate_act_sponsors` and `_subjects` directories afterwards; nothing reads them.

## How often each source changes (and how long it's cached)

| Loader                        | Upstream changes                             | Cache policy                                                               | Suggested run                                         |
| ----------------------------- | -------------------------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------- |
| mo_house                      | daily in session (Jan–May), rarely otherwise | session zips weekly (current year), monthly (past); roll-call PDFs forever | daily in session, weekly otherwise                    |
| mo_senate                     | daily in session                             | current-year listing daily, past monthly; journal PDFs forever             | daily in session, weekly otherwise                    |
| mo_senate_topics              | daily in session (new bills indexed)         | current year daily, past years monthly                                     | daily in session, weekly otherwise                    |
| mo_senate_bills               | daily in session (new bills and actions)     | current year 1 day, past years 30 days; ~1 request/s, one per bill         | daily in session, weekly otherwise (a full year is ~17 min cold) |
| mo_revisor | mostly each 28 August (new laws take effect), plus emergency clauses and contingent dates | table of contents, chapter lists and repeals list 7 days; section pages 180 days (a new version is a new URL) | weekly; never above ~1 request/s from one IP (the site blocks the IP, browsers included; requests from all shards share one 2 s pacing lock) |
| mec (opt-in)                  | continuously                                 | exports: current year weekly, past years monthly                           | weekly                                                |
| tap_mec                       | frozen (ends 2022)                           | 30 days                                                                    | monthly                                               |
| fec                           | weekly bulk refresh                          | bulk zips daily; sponsor lookups 30 days                                   | weekly                                                |
| voteview                      | after each roll call                         | daily                                                                      | weekly                                                |
| mo_house_docs (stage 2)       | as bills move (new versions, notes, amendments) | PDFs of closed sessions forever (versioned file names); open session re-checked after 7 days | weekly in session, after `mo_house`; first run ~19 h at 1 request/s, so split it with `MOGOV_HOUSE_DOCS_KINDS` / `MOGOV_HOUSE_DOCS_SESSIONS` |
| house_fd                      | as filed                                     | current + previous year index daily; PDFs forever                          | weekly                                                |
| senate_efd (opt-in)           | as filed                                     | not cached (search + reports fetched each run)                             | weekly                                                |
| courtlistener_bulk            | quarterly snapshot                           | per snapshot, forever                                                      | monthly (picks up new snapshots)                      |
| courtlistener_case_bulk       | quarterly snapshot                           | downloads + filtered CSVs per snapshot, forever                            | monthly (picks up new snapshots)                      |
| courtlistener_cases (stage 2) | daily                                        | searches 30 days; case details forever                                     | weekly; token quota ~125 req/day, resumes from cache  |
| bluebook                      | every two years                              | forever per edition                                                        | when a new edition is out (`MOGOV_BLUEBOOK_EDITIONS`) |
| openstates_people             | as edited                                    | daily                                                                      | weekly                                                |
| congress_legislators          | as edited                                    | daily                                                                      | weekly                                                |
| fjc_judges                    | as appointed                                 | 30 days                                                                    | monthly                                               |
| wikidata (stage 2)            | continuously                                 | 7 days                                                                     | weekly                                                |
| shor_mccarty                  | yearly release                               | 90 days                                                                    | quarterly                                             |
| mo_employee_pay               | yearly (each January)                        | current and previous year 7 days, older 30 days                            | monthly                                               |
| mo_sos_elections              | after each canvass (about 4 weeks after an election) | PDFs forever once 4 months old; the results page and newest PDFs daily | after each election, or monthly                       |
| mo_state_expenditures         | per fiscal year, republished by the state    | current and previous year 7 days, older 30 days                            | monthly                                               |
| census_tiger                  | yearly vintage (each autumn); redistricting  | listings 7 days; shapefiles forever                                        | monthly                                               |
| epa_frs                       | state file refreshed every few months        | 30 days                                                                    | monthly                                               |
| mo_auditor                    | reports most weeks                           | current-year list 6 hours, past years 7 days; PDFs forever                 | weekly                                                |
| census_zcta                   | yearly vintage                               | forever per vintage                                                        | monthly (picks up a new vintage)                      |

Run a subset with `mogov load <loader ...>` followed by `mogov build`. For example, daily during
session:

```
uv run mogov load mo_house mo_senate --shards 4
uv run mogov build
```

## When a loader fails

- `mogov load` always runs every selected loader, even if one fails. It logs a `loader.summary` naming
  the failed loaders (their raw data is stale) and exits non-zero.
- `mogov run` is strict by default: if any loader fails, it stops before `dbt build` and exits non-zero,
  so you never build on top of a source you know is stale.
- To build anyway, name the loader you accept stale data from (repeatable), or set
  `MOGOV_ALLOW_FAILED_LOADERS=senate_efd,...` (comma-separated, merged with the flags; for compose and
  Cloud Run, where the args are fixed). Unknown names are rejected before anything loads:

  ```
  uv run mogov run --allow-failed-loader senate_efd
  ```

  It logs a `build.stale_source` warning naming each such source, builds on its previous raw data, and
  still exits non-zero (a Cloud Run job still shows the failure). A failure in any other loader still
  stops the run. Check `mogov freshness` to see how stale the data is.

## Moving the windows

- `MOGOV_LOOKBACK_YEARS` (default 10): the years of state roll calls (House and Senate). Widening it
  only fetches the new years. Narrowing it drops the old years from raw on the next run, but they stay
  in the cache.
- `MOGOV_MEC_YEARS`, `MOGOV_MEC_CROSSWALK_YEARS`, `MOGOV_FEC_CYCLES`, `MOGOV_VOTEVIEW_CONGRESSES`,
  `MOGOV_HOUSE_FD_FIRST_YEAR`: per-source windows (see each loader's docstring). Roll them forward each
  January / cycle.

## Yearly hand-maintained seeds

Each January:

- `federal_salaries`: add the new year's pay rates for Congress (senate.gov) and federal judges
  (uscourts.gov), with their sources. Until then `fct_salaries` has no federal rows for the new year.
- `legislator_seat_corrections`: check `int_mo_senate__votes` for tokens with no `person_key`. A new
  unmatched surname usually means Open States is missing or cutting short someone's term. Add the
  corrected term with its source.

## Forcing a refresh

Delete the relevant entries under `data/cache/` (named files for large downloads, such as
`data/cache/mec/`, `data/cache/fec/`; hashed names for everything else), or the whole cache. Raw
parts never need deleting by hand.

## Refreshing the frontend

The site is a static snapshot of the exports. After a sync:

```
uv run mogov export --format parquet
cd frontend && pnpm build
```

`pnpm build` reads the new parquet files and regenerates every page and per-official JSON, and prints a warning (and still succeeds) if any parquet file is older than `data/mogov.duckdb`
(or `MOGOV_DB`), meaning you built but forgot to re-export; the fix is the two commands above. The
methodology page's "data freshness" table shows each export's timestamp. `pnpm build` finishes by running the size budgets (`pnpm sizes`) and exits non-zero if a payload is over
budget or a budgeted file is missing from the output, because a new source can push one official's JSON over the per-page budget.
Set `MOGOV_SKIP_SIZE_BUDGET=1` (exactly `1`) to skip the check; `pnpm deploy:pages` and `pnpm deploy:gcs` run the same check before publishing and honour the same variable (the budgets are still enforced by a plain `pnpm sizes` unless it is set there too).

After a sync that touched rankings or sorts, run the tie check (`uv run python scripts/check_site_determinism.py --shuffle`, minutes; scheduled locally, see [environment](environment.md#checking-that-the-site-build-is-deterministic-226-459)).

Separately, the build fails if the pay-per-vote year rows (`rpt_attendance_pay`) do not add up to their dbt total for any official, which means `rpt_attendance` and `rpt_attendance_pay` were exported from different builds; re-run `mogov build` and `mogov export` together. `MOGOV_SKIP_PAY_YEARS_CHECK=1` (exactly `1`) skips that check and logs that it did.

The frontend words award periods from `rpt_awards.period_kind` (`year`, `fec_cycle`, `lifetime`); the build fails when the export has no such column or when a `fec_cycle` list has an odd period (a stale export); re-run `uv run mogov build` and `uv run mogov export`. `MOGOV_SKIP_AWARD_CYCLES_CHECK=1` (exactly `1`) skips the odd-period guard and also lets a stale export without `period_kind` build, inferring the kind from award and office (federal `least_committee_money_share` is a cycle) with a warning (re-export to stop inferring).

Every frontend export read also checks the columns declared in `frontend/src/lib/exports/requiredColumns.ts`; an export that lacks one fails the build with `stale export: <table> lacks <columns>` and the re-export commands (`uv run mogov build`, then `uv run mogov export --format parquet`). Add a table's new column to that file when the site starts selecting it.

## Checking a sync

- `uv run mogov freshness` reports how long ago each always-on loader last landed its tables. It warns
  after 8 days and errors after 32.
- `loader.landed` log lines give row counts per table and shard; `loader.failed` means the process
  exits non-zero.
- `mogov build` runs the dbt tests. `official_profile.*_status` columns show which categories have
  data per official.
