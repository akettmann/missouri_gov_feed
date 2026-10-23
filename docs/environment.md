# Building an environment from scratch

Diagrams: [pipeline](diagrams/pipeline.svg), [lineage](diagrams/lineage.svg),
[data model](diagrams/data_model.svg), and one per source; [diagrams/](diagrams/README.md) shows them all.

## Local (Windows, macOS, Linux)

1. Install [uv](https://docs.astral.sh/uv/) (it fetches Python 3.13 itself).
   For diagram edits, also install Java 8+: the pre-commit hook renders `docs/diagrams/**/*.puml` to SVG
   with a pinned PlantUML jar and its built-in Smetana layout, so Graphviz `dot` is not needed.
2. Clone the repo and install dependencies:
   ```
   uv sync
   uv run pre-commit install        # ruff + sqlfluff on commit
   ```
3. Create `.env` in the repo root (gitignored). Everything is optional; leave out what you don't have:
   ```
   MOGOV_CONTACT=you@example.com               # enables wikidata; put in the User-Agent
   FEC_API_KEY=...                              # api.data.gov key (donor aggregates)
   COURTLISTENER_TOKEN=...                      # case outcomes, higher rate limit
   MOGOV_ACCEPT_SENATE_EFD_TERMS=1              # accept the Senate eFD use statement
   MOGOV_MEC_OPT_IN=1                           # direct MEC exports; read src/mogov/loaders/mec.py first
   ```
   See the configuration table in the [README](../README.md#configuration-env-gitignored) for the rest.
4. First full load and build:
   ```
   uv run mogov run --shards 4      # stage-1 loaders (concurrent, 4 shards) -> dbt build -> stage 2 -> dbt build
   ```
   The first run is the slow one: it downloads several GB (FEC, CourtListener bulk) and parses about
   ten years of House roll-call PDFs and Senate journals. Everything fetched is cached under
   `data/cache`, so later runs are much faster.
5. Check the result: `uv run mogov build` should end with `ERROR=0`. Run `uv run mogov export` to write
   the marts and reporting tables to `data/exports/` as parquet (the default; the frontend reads only
   parquet. `--format csv` is for other tools). If you use the site, run `pnpm build` in `frontend/`
   afterwards: `pnpm preview` serves the existing `dist/` and does not rebuild.

Layout under `data/` (override the root with `MOGOV_DATA_DIR`):

| Path | Contents |
|---|---|
| `data/cache/` | HTTP cache (one file per request, keyed by URL + params) and large downloads |
| `data/raw/<table>/part-<i>-of-<N>.parquet` | Raw landings, one part per loader shard (`MOGOV_RAW_DIR`) |
| `data/mogov.duckdb` | dbt warehouse (`MOGOV_DB`) |
| `data/exports/` | `mogov export` output |

A `data/raw/<table>.parquet` file from before sharding existed is moved into
`<table>/part-000-of-001.parquet` the next time any loader runs.

## Wiping and rebuilding from scratch

Everything under `data/` can be regenerated. What you delete decides how long the rebuild takes:

| Delete | Effect |
|---|---|
| `data/mogov.duckdb` | dbt rebuilds every model from the raw parts (under a minute). |
| `data/raw/` | Every loader lands its tables again, from the cache where it can. |
| `data/exports/` | Rewritten by the next `mogov export`. |
| `data/cache/` (optional) | Everything is downloaded and parsed again. About 10 GB as of October 2026. Keep it unless you suspect a bad cached response. |

1. Stop anything using `data/` (a running `mogov`, a DuckDB shell, `dbt docs serve`). On Windows an open
   file can't be deleted.
2. Delete the warehouse, raw landings and exports (add `data/cache` for a cold rebuild):
   ```
   rm -rf data/raw data/mogov.duckdb data/exports                                   # macOS / Linux / Git Bash
   Remove-Item -Recurse -Force data/raw, data/mogov.duckdb, data/exports             # PowerShell
   ```
3. Rebuild:
   ```
   uv run mogov run --shards 4
   ```
4. Check it:
   ```
   uv run mogov build        # must end with ERROR=0
   uv run mogov freshness    # every always-on source landed just now
   uv run mogov export --format parquet
   ```
   In the run log, every loader has `loader.finished` once per shard and no `loader.failed`. A
   `dbt.placeholder` warning is expected for tables of opt-in or key-gated loaders you haven't enabled,
   and for `cl_cases` in the first dbt build (it is a stage-2 table).

How long it takes (October 2026, one Windows desktop, `--shards 4`):
- **Warm cache** (only raw and the warehouse deleted): the October 2026 full run took about 75 minutes,
  most of it filtering the CourtListener bulk files (about 50 minutes, one process) and parsing roll-call
  PDFs. A re-run 20 minutes later took about 20 minutes, still mostly PDF parsing. PDF text is now cached
  and loaders of different services run concurrently, so expect less than both.
- **Cold cache**: add the downloads, several GB (FEC bulk files, the CourtListener bulk files at about
  8 GB compressed, about ten years of House roll-call PDFs and Senate journals). The small state sites
  are fetched with pauses between requests, so plan for a few hours.

With Docker the steps are the same, against the host folder the container mounts (`./data`, or
`MOGOV_HOST_DATA`):
```
rm -rf data/raw data/mogov.duckdb data/exports
docker compose up
docker compose run --rm mogov build
docker compose run --rm mogov freshness
```

## Frontend (static site)

The voter-facing site lives in `frontend/`: Astro (static build), Observable Plot, pnpm. It is built
entirely from the parquet exports; there is no server. Data flow:
[frontend_data_flow](diagrams/frontend_data_flow.svg).

1. Install Node.js 24 LTS (`frontend/.node-version` pins the version; `>=24.22.0`) and enable pnpm
   with `corepack enable` (the version comes from `packageManager` in `frontend/package.json`).
2. Export the marts as parquet (the build reads `data/exports/*.parquet`; `MOGOV_EXPORTS` points it
   elsewhere):
   ```
   uv run mogov export --format parquet
   ```
3. Install, build and preview:
   ```
   cd frontend
   pnpm install
   pnpm build          # dist/: one page + one JSON per official, browse page, methodology
   pnpm preview        # http://localhost:4321
   pnpm sizes          # per-official payload sizes; exits 1 if any JSON is over budget (100 KB gzipped)
   ```
   If any parquet file is older than `data/mogov.duckdb` (or `MOGOV_DB`), the build warns that you
   skipped `uv run mogov export`; it never fails the build, and stays silent if the DuckDB file is absent.
4. Checks (also run by pre-commit on `frontend/` changes): `pnpm check` (astro check / TypeScript),
   `pnpm lint` (ESLint), `pnpm format:check` (Prettier).

The money and gift sections read `rpt_donor_rollup` and `rpt_gift_rollup` (dbt `reporting` schema,
exported by `mogov export`). If either export is missing, for example when the reporting models haven't
been built yet, the build falls back to deterministic **sample data** behind a visible "Sample data"
banner instead of failing (`frontend/src/lib/exports/fixtures.ts`).

"Find my officials" (`/find/`) needs the `dim_district` and `fct_official_districts` exports (the
`census_tiger` loader); ZIP-code search also needs `dim_zcta` (the `census_zcta` loader) and is left out of
the page data without it. The build simplifies the TIGER boundaries to about 50 m and writes
`dist/lookup/districts.json` (about 300 KB gzipped); the browser downloads it on the first lookup and matches the
point itself, so a visitor's location never leaves the page. Without those exports the page says the boundaries
aren't loaded.

The officials list (`/`) shows the people serving now; its year control loads earlier years from
`dist/lookup/officeholders/<year>.json`, built from `rpt_officeholders_by_year`. Without that export the page
lists today's officials only and hides the year control. Past years cover only offices with dated rosters (MO
House, MO Senate where every seat is dated, Congress, federal courts). Both the JavaScript year control and the static `dist/years/<year>/index.html` pages name the
offices a year lacks, using one shared helper (`frontend/src/lib/lookback.ts`).

Without JavaScript, the home page's `<noscript>` block links to those static `/years/<year>/` pages, one per past
year, rendered from the same rows. The year control's error message also links to the matching static page when
the JSON fetch fails.

Every name on a year page or in the year JSON links somewhere. People serving now link to their full profile; past
officeholders without one get a small page (name, offices held with years, party, district, roster source, links to
the year pages) at the same `/officials/<slug>/` path, with `slug = slugFor(name, official_id)` for both kinds.
`pastOfficeholders()` in `frontend/src/lib/exports/load.ts` assigns the slugs, so the static year pages and the
JSON cannot disagree, and the build fails on a slug collision (profile slugs included). The slug hash comes from
`official_id`, so a past page's path becomes the full profile only where the roster id equals the `dim_official` id
(Senate/Open States, Congress bioguide, federal judges `fjc`). House, statewide and state-judge ids may differ
between the roster and `dim_official` (issue #97), so those paths are not guaranteed stable. Because the same person
can therefore appear as a past entry and a current profile, a past page whose normalized full name equals a current
profile's (or another past entry's) shows a neutral "same name" cross-link; names are never merged.

Optional build-time environment: `PUBLIC_SITE_URL` (canonical site URL), `PUBLIC_REPORT_ERROR_URL`
(where "Report an error" goes; default: a prefilled GitHub issue on this repo).

### Publishing to Google Cloud Storage

The build is plain static files, so any static host works; the repo ships a script for a GCS bucket.

1. One time: create a bucket and make it serve a website (or put it behind an HTTPS load balancer with Cloud
   CDN, which is what a custom domain with HTTPS needs):
   ```
   gcloud storage buckets create gs://BUCKET --location=us-central1 --uniform-bucket-level-access
   gcloud storage buckets add-iam-policy-binding gs://BUCKET --member=allUsers --role=roles/storage.objectViewer
   gcloud storage buckets update gs://BUCKET --web-main-page-suffix=index.html --web-error-page=404.html
   ```
2. Each release, after `pnpm build` (and `pnpm sizes`):
   ```
   gcloud auth login
   MOGOV_SITE_BUCKET=BUCKET pnpm deploy:gcs --dry-run   # see what would change
   MOGOV_SITE_BUCKET=BUCKET pnpm deploy:gcs
   ```
   The bucket mirrors `dist/` (files no longer built are deleted). Hashed assets (`_astro/`) are cached for a
   year; pages for 5 minutes and JSON for an hour, so a data refresh shows up quickly. Set `PUBLIC_SITE_URL` at
   build time to the public address.

## Local, in Docker (Compose)

Needs only Docker. Data stays in `./data` on the host, in the same layout as the uv setup, so you can mix
the two. Keys come from the same `.env`.

```
docker compose up                                   # full refresh: mogov run --shards 4 (MOGOV_SHARDS)
docker compose run --rm mogov load mo_house --shards 4
docker compose run --rm mogov build
docker compose run --rm mogov export --format parquet
docker compose --profile docs up docs               # dbt docs (every model/column definition) at http://localhost:8080
```

Set `MOGOV_HOST_DATA` to use a data folder other than `./data`. On Linux, files the container writes are
owned by root.

## Sharding

Every loader splits its work into units (PDFs, files, people, report years...). A shard owns the units
where `crc32(key) % shards == shard`, so the split depends only on the keys. It doesn't depend on
listing order or on which other shards run.

| Invocation | Effect |
|---|---|
| `mogov load mo_house` | one process, all units (`part-000-of-001`) |
| `mogov load mo_house --shards 4` | all 4 shards, in a pool of worker processes |
| `mogov load mo_house --shards 4 --shard 2` | only shard 2 of 4 (for one container of a job) |
| Cloud Run job with `--tasks 4` | same as the line above, taken from `CLOUD_RUN_TASK_COUNT` / `CLOUD_RUN_TASK_INDEX` |

Loaders that talk to different services run at the same time. Each loader names its upstream service
(`mogov list` shows it), and the work is split into jobs of (one service's loaders, one shard). A pool of
`--workers` processes runs the jobs (default `$MOGOV_WORKERS`, else the larger of the shard count and
min(CPUs, 8)). Loaders of the same service run one after another within a shard, so a site never sees
more than one request stream per shard. Slow loaders (`mo_senate`, `mo_house`, `house_fd`, `mec`, `fec`,
`courtlistener_case_bulk`) start first. Each worker can use up to `MOGOV_DUCKDB_MEMORY` (default 3GB) while
it lands a table, so lower that or `--workers` on a small machine.

Each shard replaces only its own part. If you change the shard count, run every shard before the next
`dbt build`. Parts left by the old count are deleted as the new shards write theirs.

Shards on one machine share `data/cache`. When several need the same URL (every `mo_house` shard reads
every session zip, for example), the first takes a lock file next to the cache entry
(`.<entry>.lock`) and downloads it; the others wait and read its copy. A lock untouched for 5 minutes
is treated as left by a crashed process. Cloud Run tasks run on separate machines, so there the lock
only helps as far as Cloud Storage FUSE honours exclusive creates; expect some duplicate downloads.

Be polite with small state sites. Each shard keeps its own request pace, so N shards make N times the
request rate. That matters most for `mec` (ask MEC before running it in parallel) and less for the
cached PDF sources.

## Google Cloud Run jobs

The image (`Dockerfile`) runs `mogov` as its entrypoint. Logs go to stderr as JSON with
`severity`/`message` keys whenever `CLOUD_RUN_JOB` is set. A failing loader makes the task exit
non-zero. SIGTERM exits cleanly: temp files are removed and metrics are flushed.

> This setup follows the Cloud Run container contract but has not been deployed yet. Treat it as a
> starting point.

1. Create a bucket for the data and a repository for the image:
   ```
   gcloud storage buckets create gs://$BUCKET --location=$REGION
   gcloud artifacts repositories create mogov --repository-format=docker --location=$REGION
   ```
2. Build and push the image:
   ```
   gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT/mogov/mogov:latest
   ```
3. Put secrets (FEC_API_KEY, COURTLISTENER_TOKEN, MOGOV_CONTACT) in Secret Manager.
4. Create one job per loader group. Mount the bucket with Cloud Storage FUSE at `/data` (the image sets
   `MOGOV_DATA_DIR=/data`):
   ```
   gcloud run jobs create mogov-load-votes \
     --image $REGION-docker.pkg.dev/$PROJECT/mogov/mogov:latest \
     --region $REGION --tasks 8 --parallelism 8 --task-timeout 3h --max-retries 1 \
     --memory 4Gi --cpu 2 \
     --add-volume name=data,type=cloud-storage,bucket=$BUCKET \
     --add-volume-mount volume=data,mount-path=/data \
     --set-env-vars MOGOV_DUCKDB_MEMORY=2GB \
     --set-secrets COURTLISTENER_TOKEN=courtlistener-token:latest \
     --args load,mo_house,mo_senate,mo_senate_topics,house_fd
   ```
   Retrying a task is safe: it re-runs the same shard and replaces the same part.
5. Create the build job. DuckDB does random writes, which Cloud Storage FUSE handles badly, so build in
   the container's in-memory filesystem and copy the finished database back:
   ```
   gcloud run jobs create mogov-build ... --tasks 1 --memory 8Gi \
     --command sh --args -c,'cp /data/mogov.duckdb /tmp/ 2>/dev/null; MOGOV_DB=/tmp/mogov.duckdb mogov build && cp /tmp/mogov.duckdb /data/mogov.duckdb'
   ```
6. Chain them in order: stage-1 load jobs, then `mogov-build`, then
   `mogov load courtlistener_cases wikidata` (stage 2; `mogov list` shows each loader's stage), then
   `mogov-build` again. Use Cloud Workflows, or Cloud Scheduler triggers spaced far
   enough apart. See [sync.md](sync.md) for cadences.

Metrics: set `OTEL_EXPORTER_OTLP_ENDPOINT` to an OTLP/HTTP collector, for example an OpenTelemetry
Collector sidecar that exports to Cloud Monitoring.
