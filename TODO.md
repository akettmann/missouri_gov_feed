# TODO List

## Low priority
- [ ] dbt best-practice decisions (see docs/dbt_best_practices.md): split the single `raw` source into one source per system? enforce model contracts on the marts? add dbt unit tests for the name-matching models? add exposures once the frontend exists?
- [] build a Docker Compose file

## Future
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end (for now the pipeline runs and writes locally)
