# Building an environment from scratch

Diagrams: [pipeline](diagrams/pipeline.puml), [lineage](diagrams/lineage.puml),
[data model](diagrams/data_model.puml), and one per source under [diagrams/sources](diagrams/sources).

## Local (Windows, macOS, Linux)

1. Install [uv](https://docs.astral.sh/uv/) (it fetches Python 3.13 itself).
   For diagram edits, also install Java 8+: the pre-commit hook renders `docs/diagrams/**/*.puml` to SVG
   with a pinned PlantUML jar.
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
   uv run mogov run --shards 4      # stage-1 loaders (4 processes) -> dbt build -> stage 2 -> dbt build
   ```
   The first run is the slow one: it downloads several GB (FEC, CourtListener bulk) and parses about
   ten years of House roll-call PDFs and Senate journals. Everything fetched is cached under
   `data/cache`, so later runs are much faster.
5. Check the result: `uv run mogov build` should end with `ERROR=0`. Run `uv run mogov export` to write
   the marts to `data/exports/`.

Layout under `data/` (override the root with `MOGOV_DATA_DIR`):

| Path | Contents |
|---|---|
| `data/cache/` | HTTP cache (one file per request, keyed by URL + params) and large downloads |
| `data/raw/<table>/part-<i>-of-<N>.parquet` | Raw landings, one part per loader shard (`MOGOV_RAW_DIR`) |
| `data/mogov.duckdb` | dbt warehouse (`MOGOV_DB`) |
| `data/exports/` | `mogov export` output |

A `data/raw/<table>.parquet` file from before sharding existed is moved into
`<table>/part-000-of-001.parquet` the next time any loader runs.

## Sharding

Every loader splits its work into units (PDFs, files, people, report years...). A shard owns the units
where `crc32(key) % shards == shard`, so the split depends only on the keys. It doesn't depend on
listing order or on which other shards run.

| Invocation | Effect |
|---|---|
| `mogov load mo_house` | one process, all units (`part-000-of-001`) |
| `mogov load mo_house --shards 4` | a pool of 4 processes, one per shard |
| `mogov load mo_house --shards 4 --shard 2` | only shard 2 of 4 (for one container of a job) |
| Cloud Run job with `--tasks 4` | same as the line above, taken from `CLOUD_RUN_TASK_COUNT` / `CLOUD_RUN_TASK_INDEX` |

Each shard replaces only its own part. If you change the shard count, run every shard before the next
`dbt build`. Parts left by the old count are deleted as the new shards write theirs.

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
     --args load,mo_house,mo_senate,house_fd
   ```
   Retrying a task is safe: it re-runs the same shard and replaces the same part.
5. Create the build job. DuckDB does random writes, which Cloud Storage FUSE handles badly, so build in
   the container's in-memory filesystem and copy the finished database back:
   ```
   gcloud run jobs create mogov-build ... --tasks 1 --memory 8Gi \
     --command sh --args -c,'cp /data/mogov.duckdb /tmp/ 2>/dev/null; MOGOV_DB=/tmp/mogov.duckdb mogov build && cp /tmp/mogov.duckdb /data/mogov.duckdb'
   ```
6. Chain them in order: stage-1 load jobs, then `mogov-build`, then `mogov load courtlistener_cases`
   (stage 2), then `mogov-build` again. Use Cloud Workflows, or Cloud Scheduler triggers spaced far
   enough apart. See [sync.md](sync.md) for cadences.

Metrics: set `OTEL_EXPORTER_OTLP_ENDPOINT` to an OTLP/HTTP collector, for example an OpenTelemetry
Collector sidecar that exports to Cloud Monitoring.
