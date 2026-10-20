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
## ETL
DBT Core
DuckDB backend
Use compatible constructs from DBT to make switching backends possible
linting: SqlFluff
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
* Frontend issues go in `FRONTEND_TODO.md`
* all other issues go to `TODO.md`
* If you find a problem while working, if it is not blocking your progress, offload it to the proper todo file.
* Put them in sections of low/medium/high priority
