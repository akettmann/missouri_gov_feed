# TODO List

# High Priority
- [ ] Re-run `uv run mogov run --shards 4` once more to confirm the lock fix (no `loader.failed`) and that no progress bars appear in the log. Expected warnings: `courtlistener_cases` quota, `dbt.placeholder` for stage-2 tables in the first build, `census_tiger.not_a_zip` for the unpublished TIGER2026 SLDL

## Frontend support (see FRONTEND_TODO.md)
### Loaders
- [ ] Remaining bill-subject gaps: pre-2024 House bills that never reached the Senate, and House roll calls on Senate bills (the House export doesn't name them)

### Later (interest vs. vote overlap)
- [ ] Widen `interest_keywords` coverage: classified names cover ~37% of organization money; most of the rest is opaque PAC acronyms (AMECPAC, MEDA PAC, CN-MO PAC...) that need a person to look up whom they represent

## Low priority
- [ ] Listing of companies that operate in the official's jurisdiction, highlight which ones have donated. Needs a decision on the source: the MO Secretary of State business search has no bulk export; Census County Business Patterns has counts but no names
- [ ] Each January: add the year's rates to the `federal_salaries` seed (senate.gov, uscourts.gov)

## Future
- [ ] Deploy the Cloud Run jobs described in docs/environment.md and confirm the GCS FUSE layout end to end (for now the pipeline runs and writes locally)
- [ ] Sunshine Law (RSMo 610) requests for Missouri personal financial disclosures (PFDs), which are not published online: officials' and candidates' from MEC (helpdesk@mec.mo.gov, 800-392-8660), judges' from the Clerk of the Missouri Supreme Court. Once copies arrive, add them through a seed or a local-folder loader
