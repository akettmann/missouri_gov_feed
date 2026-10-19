# TODO List

## Low priority
- [ ] Add dbt exposures once the frontend exists (docs/dbt_best_practices.md)
- [ ] Document "wipe and rebuild from scratch" in docs/environment.md: what to delete (data/raw, mogov.duckdb, exports; optionally data/cache), `mogov run --shards 4`, verification (`mogov build`, `mogov freshness`), and expected time with vs. without the cache; Docker variant

## Future
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end (for now the pipeline runs and writes locally)
