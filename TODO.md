# TODO List

## High priority
- [ ] Senate votes that match no senator (`int_mo_senate__votes.person_key` null): Wallingford (1,106 tokens, 2017-2020), Kehoe (663, 2017-2018), and every senator on the January 4-10, 2017 votes. Their seats seem to be missing from `int_mo_legislators__seats` (former senators, or terms starting after the first day of session). Find the gap in the Open States people data and fill it (seed or another source)

## Medium priority
- [ ] Send the Sunshine Law requests for personal financial disclosures (templates in docs/sunshine_requests.md): MEC for legislators, statewide officials and candidates; the Clerk of the Supreme Court for judges. Fill in the project description and contact, build the filer lists from `dim_official`, log the dates sent. Load the copies that come back through a seed or a local-folder loader
- [ ] Bill subjects for pre-2024 House bills that never reached the Senate. The House XML has no `SubjectIndex` before 2024 and the House site no longer serves older subject indexes. Candidate sources:
  - LegiScan: free API key (30,000 queries/month), weekly per-state datasets with bills, subjects, sponsors and roll calls. Check the license and Missouri's coverage years
  - Open States bulk session CSVs: Missouri 2017-2026, free login; check whether they carry subjects
- [ ] Widen `interest_keywords` coverage (44% of organization contributions and lobbyist gifts by amount, October 2026). Largest unclassified: Missouri Justice PAC, Paladin PAC, CN-MO PAC, A Better Missouri PAC, MHA PAC (not the hospital association; its PAC is HEALTHPAC), Living Well PAC, RQC PAC, HBS MO State PAC, the MBA region PACs, Dealers Interested in Government. Many are leadership or lobbyist pass-through PACs with no single industry. Add a keyword only once its sponsor is confirmed. Where to look:
  - MEC's Statement of Committee Organization ("Connected Organization's Name" field), on scanned filings at `mec.mo.gov/Scanned/PDF/...`
  - FEC committee data (`connected_organization_name`) for federally registered PACs; the `fec` loader already uses that API
  - FollowTheMoney (now part of OpenSecrets) industry codes for state contributors; check whether its API or downloads are still offered
- [ ] Campaign contributions whose payer is "NONE" ($1.27M, October 2026): find which reports or loaders produce it, and use the real name if the source has one
- [ ] `fct_federal_donor_summary`: some cycles' `by_size` buckets sum to far more than the cycle's `individual contributions` total (Hawley 2024: 1.96x; S001195 2024 and 2026: 1.3x; most members are 1.00-1.11x). Likely the API aggregates span more committees (joint fundraising, a second campaign) than the candidate summary. Find which committees feed each side and make them match
- [ ] Federal judicial disclosures (AO-10): some scanned filings' OCR text reaches `fct_family_ties` / `fct_commercial_ties` as garbage, e.g. Judge Bowman's (fjc:1378081) spouse income row "2200 =oK00 =o OL00 Es 0. B1=$1,000,001:$5,000,000 + P4=More than $50,000,000". Detect low-quality OCR rows (few dictionary words, stray `=`) and flag or drop them in staging
- [ ] `scripts/gen_model_docs.py` overwrites each `_<source>__models.yml` from the SQL headers, so it deletes hand-added column tests: rerunning it (October 2026) dropped the `session_day` accepted_range sanity check on `stg_mo_house__rollcalls`. Make it merge into the existing columns (or keep tests in a separate file, like the unit tests)
- [ ] `fct_vote_bills`: House roll calls on combined bills (`HCS HBs 267 & 347`, `SS SCS SBs 49 & 118`) link only the lead bill. Link every bill number in the measure if bill-level reports need the others
- [ ] Warning when running DBT via `uv run mogov run --shards 4`
```shell
2026-10-20T03:05:37.657895Z [info     ] loader.landed                  loader=mo_house rows=1844 shard=2/4 table=raw.mo_house_rollcalls
2026-10-20T03:05:37.657994Z [info     ] loader.landed                  loader=mo_house rows=295388 shard=2/4 table=raw.mo_house_rollcall_votes
2026-10-20T03:05:37.658104Z [info     ] loader.finished                loader=mo_house seconds=504.3 shard=2/4
<frozen runpy>:128: RuntimeWarning: 'dbt.cli.main' found in sys.modules after import of package 'dbt.cli', but prior to execution of 'dbt.cli.main'; this may result in unpredictable behaviour
03:05:41  Running with dbt=1.12.6
03:05:42  Registered adapter: duckdb=1.11.0
03:05:45  Found 108 models, 102 data tests, 10 seeds, 65 sources, 1 exposure, 655 macros, 5 unit tests
03:05:45
03:05:45  Concurrency: 4 threads (target='local')
```

## Low priority
- [ ] Add a defense industry (Boeing, General Dynamics, Northrop Grumman, RTX are large federal donors) to `interest_keywords` and `industry_subjects`
- [ ] Listing of companies that operate in the official's jurisdiction, highlighting the ones that donated. Source options:
  - Secretary of State business entity registry: no bulk export. Request an extract under the Sunshine Law (template in docs/sunshine_requests.md)
  - Missouri Accountability Portal (mapyourtaxes.mo.gov) downloads: state payments by vendor per fiscal year, pipe-delimited
  - EPA Facility Registry Service or OSHA establishment data: named, geocoded sites for regulated industries only
  - Census County Business Patterns: counts by industry, no company names
- [ ] Write a simplified summary of the Missouri Sunshine Law (full text in docs/reference/rsmo_chapter_610_sunshine_law.md): what's open, what can be closed, how to request records, deadlines, fees and remedies
- [ ] Each January: add the year's rates to the `federal_salaries` seed (senate.gov, uscourts.gov)
- [ ] PlantUML in Github doesn't seem to have dot installed. Can we use the new Javascript transpile of plantuml?
