# Keeping an environment's data in sync

Every loader is idempotent. Re-running one replaces its raw parts with a fresh landing, and the HTTP
cache decides what actually goes back to the network. So "syncing" just means running the pipeline
again:

```
uv run mogov run --shards 4
```

## How often each source changes (and how long it's cached)

| Loader | Upstream changes | Cache policy | Suggested run |
|---|---|---|---|
| mo_house | daily in session (Jan–May), rarely otherwise | session zips weekly (current year), monthly (past); roll-call PDFs forever | daily in session, weekly otherwise |
| mo_senate | daily in session | current-year listing daily, past monthly; journal PDFs forever | daily in session, weekly otherwise |
| mec (opt-in) | continuously | exports: current year weekly, past years monthly | weekly |
| tap_mec | frozen (ends 2022) | 30 days | monthly |
| fec | weekly bulk refresh | bulk zips daily; sponsor lookups 30 days | weekly |
| voteview | after each roll call | daily | weekly |
| house_fd | as filed | current + previous year index daily; PDFs forever | weekly |
| senate_efd (opt-in) | as filed | not cached (search + reports fetched each run) | weekly |
| courtlistener_bulk | quarterly snapshot | per snapshot, forever | monthly (picks up new snapshots) |
| courtlistener_case_bulk | quarterly snapshot | downloads + filtered CSVs per snapshot, forever | monthly (picks up new snapshots) |
| courtlistener_cases (stage 2) | daily | searches 30 days; case details forever | weekly; token quota ~125 req/day, resumes from cache |
| bluebook | every two years | forever per edition | when a new edition is out (`MOGOV_BLUEBOOK_EDITIONS`) |
| openstates_people | as edited | daily | weekly |
| congress_legislators | as edited | daily | weekly |
| fjc_judges | as appointed | 30 days | monthly |
| wikidata | continuously | 7 days | weekly |
| acu_ratings | yearly | 30 days | monthly |
| shor_mccarty | yearly release | 90 days | quarterly |

Run a subset with `mogov load <loader ...>` followed by `mogov build`. For example, daily during
session:

```
uv run mogov load mo_house mo_senate --shards 4
uv run mogov build
```

## Moving the windows

- `MOGOV_LOOKBACK_YEARS` (default 10): the years of state roll calls (House and Senate). Widening it
  only fetches the new years. Narrowing it drops the old years from raw on the next run, but they stay
  in the cache.
- `MOGOV_MEC_YEARS`, `MOGOV_MEC_CROSSWALK_YEARS`, `MOGOV_FEC_CYCLES`, `MOGOV_VOTEVIEW_CONGRESSES`,
  `MOGOV_HOUSE_FD_FIRST_YEAR`: per-source windows (see each loader's docstring). Roll them forward each
  January / cycle.

## Forcing a refresh

Delete the relevant entries under `data/cache/` (named files for large downloads, such as
`data/cache/mec/`, `data/cache/fec/`; hashed names for everything else), or the whole cache. Raw
parts never need deleting by hand.

## Checking a sync

- `loader.landed` log lines give row counts per table and shard; `loader.failed` means the process
  exits non-zero.
- `mogov build` runs the dbt tests. `official_profile.*_status` columns show which categories have
  data per official.
