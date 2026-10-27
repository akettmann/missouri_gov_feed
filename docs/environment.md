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

   `run` is strict: if any loader fails it stops before `dbt build`, logs `build.skipped` naming the failed
   loaders, and exits non-zero. Fix the cause and re-run (loaders are idempotent), or, for a known-flaky
   source, build on its last landed data with `uv run mogov run --allow-failed-loader <source>` or
   `MOGOV_ALLOW_FAILED_LOADERS=<source>[,<source>]` (env var form for compose / Cloud Run, where the args are
   fixed). Until [#161](https://github.com/akettmann/missouri_gov_feed/issues/161) lands, if you opted in to
   `senate_efd` (`MOGOV_ACCEPT_SENATE_EFD_TERMS=1`) you will need `MOGOV_ALLOW_FAILED_LOADERS=senate_efd`.

   The first run is the slow one: it downloads several GB (FEC, CourtListener bulk) and parses about
   ten years of House roll-call PDFs and Senate journals. The statutes (`mo_revisor`) take longest, about
   17 hours: revisor.mo.gov blocks any IP that reads faster than about one page a second, so the loader
   reads ~30,000 section-version pages 2 s apart, however many shards run (a lock in `data/cache` spaces
   every process's requests; it needs one filesystem, so on Cloud Run use a single task). The first full load took about 52 minutes
   on top of a warm cache; an interrupted run keeps its fetched pages in the cache and resumes from them. Avoid browsing revisor.mo.gov
   from the same IP during the load: that traffic counts toward the limit too. Everything fetched is cached under
   `data/cache`, so later runs are much faster.

5. Check the result: `uv run mogov build` should end with `ERROR=0`. Run `uv run mogov export` to write
   the marts and reporting tables to `data/exports/` as parquet (the default; the frontend reads only
   parquet. `--format csv` is for other tools). If you use the site, run `pnpm build` in `frontend/`
   afterwards: `pnpm preview` serves the existing `dist/` and does not rebuild.

Layout under `data/` (override the root with `MOGOV_DATA_DIR`):

| Path                                       | Contents                                                                     |
| ------------------------------------------ | ---------------------------------------------------------------------------- |
| `data/cache/`                              | HTTP cache (one file per request, keyed by URL + params) and large downloads |
| `data/raw/<table>/part-<i>-of-<N>.parquet` | Raw landings, one part per loader shard (`MOGOV_RAW_DIR`)                    |
| `data/raw/mo_house_xml/<session>/*.gz`     | Raw files landed unchanged, gzipped; `mo_house_xml_files` records each path  |
| `data/mogov.duckdb`                        | dbt warehouse (`MOGOV_DB`)                                                   |
| `data/exports/`                            | `mogov export` output                                                        |

A `data/raw/<table>.parquet` file from before sharding existed is moved into
`<table>/part-000-of-001.parquet` the next time any loader runs.

## Wiping and rebuilding from scratch

Everything under `data/` can be regenerated. What you delete decides how long the rebuild takes:

| Delete                   | Effect                                                                                                                       |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `data/mogov.duckdb`      | dbt rebuilds every model from the raw parts (under a minute).                                                                |
| `data/raw/`              | Every loader lands its tables again, from the cache where it can.                                                            |
| `data/exports/`          | Rewritten by the next `mogov export`.                                                                                        |
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
   pnpm build          # dist/: one page + one JSON per official, browse page, methodology; then runs the size budgets (exits 1 if over; MOGOV_SKIP_SIZE_BUDGET=1 skips them); loading the exports also fails the build if `rpt_attendance_pay` year rows do not match `rpt_attendance` (exports from different builds; `MOGOV_SKIP_PAY_YEARS_CHECK=1`, exactly `1`, skips that check and logs it); the frontend reads `rpt_awards.period_kind` (`year` / `fec_cycle` / `lifetime`) and fails if the export has no such column (re-export) or if a `fec_cycle` list has an odd period; `MOGOV_SKIP_AWARD_CYCLES_CHECK=1` (exactly `1`) skips the odd-period guard and also lets a stale export without `period_kind` build, inferring the kind from award and office (federal `least_committee_money_share` is a cycle) with a warning
   pnpm preview        # http://localhost:4321
   pnpm sizes          # the same check on its own: per-official payload sizes (exits 1 if any JSON is over 100 KB gzipped) and the lookup/districts.json and /awards budgets in scripts/size-budget.mjs
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
House, MO Senate (seats dated from the journal roll calls where Open States has no start or a wrong end), Congress, federal courts). Both the JavaScript year control and the static `dist/years/<year>/index.html` pages name the
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

The businesses section of a profile carries only the donor-tied sites and counts by industry (a U.S. House
district holds about 10,000 EPA-regulated sites). The full list per district or city is built from
`fct_jurisdiction_businesses` into `dist/districts/<district>/sites/index.html` (a plain table, no JavaScript
needed) and `dist/districts/<district>/sites.csv`, 201 districts in all; `<district>` is the `district_id` with
`:` replaced by `-` (`state_house-135`). Donor-tied rows name the donor, link to where the contributions are filed
and carry the "possible match" badge, so the "Hide possible matches" toggle applies; the CSV has the same columns.
`lib/exports/districtSites.ts` reads `fct_jurisdiction_businesses` and `fct_jurisdiction_business_donors` once each (two queries, grouped in memory) and fails the build if a
district maps to several officials or an official to several districts. Measured on this machine against main
(about 218k site rows, 402 extra routes): `dist/` 64 MB to 174 MB; peak node memory about 0.6-0.7 GB to about
1.0 GB; build time 100-121 s on main vs 78-113 s with the pages (three runs; machine load varied more than the
difference, so no measurable cost). An earlier per-route query version took about 70 s more and ran out of memory
in 2 of 5 builds.
Without the export no site pages are built and the section shows no link.

Optional build-time environment: `PUBLIC_SITE_URL` (canonical site URL), `PUBLIC_BASE_PATH` (path prefix such as `/missouri_gov_feed`; unset =
site at the root, set by `deploy:pages`), `PUBLIC_REPORT_ERROR_URL`
(where "Report an error" goes; default: a prefilled GitHub issue on this repo).

### Checking that the site build is deterministic (#226, #459)

Two builds of the same data must give byte-identical output, including on tied rows (a ranking that ends on a tie
without a tiebreaker). `scripts/check_site_determinism.py` builds the site twice and diffs every file; with
`--shuffle` the second build reads a copy of the exports with their rows in random order, which exposes ties that the
engine happened to read the same way twice:

```
uv run python scripts/check_site_determinism.py --shuffle     # exit 1 and a file list on any difference
```

It runs on the local exports and takes two site builds (minutes), so there is no GitHub Actions job for it: CI has no
`data/exports` (local and gitignored), and a fixture export covering the roughly 90 tables the site reads would not
hold real ties. Run it by hand after touching a ranking, a sort or an award, and on a schedule on the machine that
holds the exports, after the weekly `mogov run` and `mogov export` (see [sync](sync.md)). For example, Windows Task
Scheduler (weekly, Sunday 06:00; adjust the path):

```
schtasks /create /tn mogov-determinism /sc weekly /d SUN /st 06:00 /tr "cmd /c cd /d C:\path\to\missouri_gov_feed && uv run python scripts/check_site_determinism.py --shuffle >> data\determinism.log 2>&1"
```

or cron: `0 6 * * 0 cd ~/missouri_gov_feed && uv run python scripts/check_site_determinism.py --shuffle >> data/determinism.log 2>&1`.
A non-zero exit means a tie needs a tiebreaker; fix the model or page, do not skip the check. What CI does cover is the
script's compare and shuffle logic (`tests/test_site_determinism.py`: a tied sort is flagged, a total order passes).

### Publishing to Google Cloud Storage

The build is plain static files, so any static host works; the repo ships a script for a GCS bucket.

1. One time: create a bucket and make it serve a website (or put it behind an HTTPS load balancer with Cloud
   CDN, which is what a custom domain with HTTPS needs):
   ```
   gcloud storage buckets create gs://BUCKET --location=us-central1 --uniform-bucket-level-access
   gcloud storage buckets add-iam-policy-binding gs://BUCKET --member=allUsers --role=roles/storage.objectViewer
   gcloud storage buckets update gs://BUCKET --web-main-page-suffix=index.html --web-error-page=404.html
   ```
2. Each release, after `pnpm build`:
   ```
   gcloud auth login
   MOGOV_SITE_BUCKET=BUCKET pnpm deploy:gcs --dry-run   # see what would change
   MOGOV_SITE_BUCKET=BUCKET pnpm deploy:gcs
   ```
   The bucket mirrors `dist/` (files no longer built are deleted). Hashed assets (`_astro/`) are cached for a
   year; pages for 5 minutes and JSON for an hour, so a data refresh shows up quickly. Set `PUBLIC_SITE_URL` at
   build time to the public address.

### Publishing to GitHub Pages (free stopgap)

GCS (above) stays the end goal; Pages is a free stopgap while traffic is tiny. The site is built **locally** (CI has no data) and pushed to an
orphan `gh-pages` branch; `main` history is never touched.

Findings (checked against the ~200 MB `dist/`, 1052 pages):

- Limits: a published Pages site must be <= 1 GB, each file < 100 MB (git push limit), and the soft bandwidth cap is
  100 GB/month. Our `dist/` is about 200 MB, the largest file is a 4.4 MB HTML page, so it fits comfortably.
  `deploy:pages` refuses to push if either limit would be broken.
- Method (a), orphan `gh-pages` branch from a temp dir, was chosen over (b) `workflow_dispatch` +
  `upload-pages-artifact`: (b) needs the built site inside CI, and CI has no data, so we would have to upload 200 MB
  from a laptop anyway. (a) is one command, needs no workflow, and force-pushing the orphan branch replaces history
  so snapshots do not accumulate.
- Project sites are served under `/missouri_gov_feed/`, so the build sets Astro `base` from `PUBLIC_BASE_PATH`.
  Every internal link goes through `href()` (`src/lib/site.ts`); the default (GCS) build has no base and is
  unchanged. `scripts/link-check.mjs` verifies a built `dist/` (every root-relative reference resolves under the base).

Differences from GCS to keep in mind: Pages sends no custom `Cache-Control` headers (a fixed short cache; our
year-long `_astro/` caching and 5-minute page caching do not apply), infers content types from file extensions,
serves `404.html` for unknown paths, and 301-redirects a directory URL without a trailing slash to the slash form.
The Pages build and the GCS build differ (base path), so **rebuild before `deploy:gcs`**: it refuses a dist built
for Pages (link check at the root), and `deploy:pages` rebuilds with the Pages base itself.

```sh
pnpm deploy:pages --dry-run   # build with the Pages base, stale check, link check, size check; pushes nothing
pnpm deploy:pages             # the same, then force-push ONLY the gh-pages branch
```

One-time setup, in the repo on GitHub: Settings -> Pages -> Build and deployment -> Source "Deploy from a branch",
Branch `gh-pages`, folder `/ (root)`. The site then appears at https://akettmann.github.io/missouri_gov_feed/ a minute
after each push. Note that Pages sites from a public repo are public; use `--allow-stale` only deliberately.
On Windows Git Bash never set `PUBLIC_BASE_PATH=/x` by hand (MSYS rewrites it to a `C:/Program Files/Git/...` path;
the build now rejects that); the script sets it for you.

The deploy only ever writes the `gh-pages` branch (there is no `--branch` flag), pushing to
`https://github.com/<owner>/<name>.git` for the repo of the `origin` remote (`--remote NAME` picks another remote
to read the repo from). It refuses to run with uncommitted changes under `frontend/` (`--allow-dirty` overrides)
and removes its ~200 MB temp repo on every exit, dry runs and failures included (`--keep` leaves it for
inspection). It can be started from any directory. It runs the size budget check (as `pnpm build` does) before publishing, including with `--skip-build`; `MOGOV_SKIP_SIZE_BUDGET=1` skips it, as it does for `pnpm deploy:gcs`. If deleting the temp repo fails (for example EBUSY) during an interrupt, the interrupt result stays (exit 130) and the left-over directory is named in an extra warning.

A Ctrl+C before the push starts stops it. What happens depends on the stage:

| Stage                                       | Ctrl+C result                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm build`                                | Node's default handler (no listener is installed yet) kills the script and the build; no temp dir exists yet; exit code is the signal's (on Windows typically `0xC000013A`).                                                                                                                                                                                                                 |
| `pnpm build` / link check                   | Same as the build: no listener is installed yet, so Node's default handler kills the script (the link check is a child process); no temp dir exists yet.                                                                                                                                                                                                                                     |
| Copy of `dist/` and size scan               | The first Ctrl+C deletes the temp repo (unless `--keep`) and exits 130 ("Interrupted; nothing was pushed.").                                                                                                                                                                                                                                                                                 |
| `git init` / `add` / `commit` / `rev-parse` | These run as asynchronous child processes, so the same listener handles the signal: temp repo deleted, exit 130. If git itself dies from the Ctrl+C first (status 130 or `0xC000013A`), that is reported as "Interrupted; nothing was pushed.", also exit 130. An interrupt flag is also checked (after yielding to the event loop) before every git step and immediately before `git push`. |
| `git push`                                  | If Ctrl+C arrives after the push has started the script exits 130 with "the push may or may not have completed"; check the `gh-pages` branch.                                                                                                                                                                                                                                                |

A second Ctrl+C while the temp repo is being deleted is ignored until the deletion finishes, so no ~200 MB directory is
left in the temp folder.

The repo is always taken from a GitHub remote URL (`https://github.com/o/n`, `git@github.com:o/n`, or
`ssh://git@github.com/o/n`). Explicit ports, `ssh.github.com:443` and SSH host aliases are not recognised; use a
plain github.com URL for the remote, or point `--remote` at a remote that has one.

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

`docker compose up` runs `mogov run`, which is strict: if any loader fails it stops before `dbt build` and
exits non-zero. To build anyway on the last landed raw data of a known-flaky source, set
`MOGOV_ALLOW_FAILED_LOADERS=<source>[,<source>]` (shell or `.env`; compose passes it through). The exit code
stays non-zero.

## Sharding

Every loader splits its work into units (PDFs, files, people, report years...). A shard owns the units
where `crc32(key) % shards == shard`, so the split depends only on the keys. It doesn't depend on
listing order or on which other shards run.

| Invocation                                 | Effect                                                                             |
| ------------------------------------------ | ---------------------------------------------------------------------------------- |
| `mogov load mo_house`                      | one process, all units (`part-000-of-001`)                                         |
| `mogov load mo_house --shards 4`           | all 4 shards, in a pool of worker processes                                        |
| `mogov load mo_house --shards 4 --shard 2` | only shard 2 of 4 (for one container of a job)                                     |
| Cloud Run job with `--tasks 4`             | same as the line above, taken from `CLOUD_RUN_TASK_COUNT` / `CLOUD_RUN_TASK_INDEX` |

Loaders that talk to different services run at the same time. Each loader names its upstream service
(`mogov list` shows it), and the work is split into jobs of (one service's loaders, one shard). A pool of
`--workers` processes runs the jobs (default `$MOGOV_WORKERS`, else the larger of the shard count and
min(CPUs, 8)). Loaders of the same service run one after another within a shard, so a site never sees
more than one request stream per shard. Slow loaders (`mo_senate`, `mo_house`, `house_fd`, `mec`, `fec`,
`courtlistener_case_bulk`) start first. Each worker can use up to `MOGOV_DUCKDB_MEMORY` (default 3GB) while
it lands a table, so lower that or `--workers` on a small machine.

Each shard replaces only its own part. If you change the shard count, run every shard before the next
`dbt build`. Parts left by the old count are deleted as the new shards write theirs.

Only one run may write a given table's shard at a time. A sink takes an exclusive OS lock on
`data/raw/<table>/.part-<i>-of-<N>.parquet.lock` when it opens and holds it until it finishes. A second
`mogov load` of the same shard fails at once with `ShardBusyError: another run is already writing <table>
shard i of N`, and the first run is untouched. Different shards don't conflict. The OS drops the lock when the
process exits, even if it was killed, so a crash never leaves a lock that blocks the next run (the empty
`.lock` files are harmless; dbt reads only `*.parquet`). The lock covers one machine or any filesystem with
working file locks. On a mount without them (some network or FUSE volumes) the sink logs
`shard_lock_unsupported` and runs unlocked, so on Cloud Run keep one task per shard (the default).

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
The jobs below chain `load` and `build` as separate jobs, so a failed load job already stops the chain. If you
instead run `mogov run` as a job, it is strict by default; set `MOGOV_ALLOW_FAILED_LOADERS=<source>` (via
`--set-env-vars`) to tolerate a known-flaky source.

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
