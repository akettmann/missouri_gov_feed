# TODO List

## High priority
- [ ] Re-run `uv run mogov run --shards 4` once more to confirm the lock fix (no `loader.failed`) and that no progress bars appear in the log. Expected warnings: `courtlistener_cases` quota, `dbt.placeholder` for stage-2 tables in the first build, `census_tiger.not_a_zip` for the unpublished TIGER2026 SLDL
- [ ] `mo_house`: discover roll-call PDFs by enumerating `billsYYS/rollcalls/{day}.{nnn}.pdf` per session day, not only through the bill XML. The XML misses House votes on Senate bills and procedural votes (see the `mo_house` quirks in docs/sources.md). Link the new ones to bills with the PDF's `measure` header (`SS SCS SBs 49 & 118`). Check `rpt_attendance` afterwards: it currently counts only the roll calls we found
- [ ] `fct_vote_bills`: 833 House roll calls that name a House bill (`HCS HB 2`, `HB 1973`...) aren't linked to it, because the bill XML doesn't nest them. Fall back to matching the PDF `measure` to the bill number

## Medium priority
- [ ] Send the Sunshine Law requests for personal financial disclosures (templates and requirements in docs/sunshine_requests.md): MEC for legislators, statewide officials and candidates; the Clerk of the Supreme Court for judges. Fill in the project description and contact, build the filer lists from `dim_official`, then log the dates sent. Once copies arrive, add them through a seed or a local-folder loader
- [ ] Bill subjects for pre-2024 House bills that never reached the Senate (the House XML has no `SubjectIndex` before 2024, and the House site's subject index keeps only a few years: 2017-2024 return nothing, the static `sbjndx` archive stops at 2011). Candidates:
  - LegiScan: free API key (30,000 queries/month), weekly per-state datasets (JSON/CSV) with bills, subjects, sponsors and roll calls. Check the license terms and Missouri's coverage years before building a loader
  - Open States bulk session CSVs: Missouri 2017-2026, free account login required; check whether they carry subjects
- [ ] Widen `interest_keywords` coverage: classified names cover ~37% of organization money; most of the rest is opaque PAC acronyms (AMECPAC, MEDA PAC, CN-MO PAC...). Sources to look up whom they represent:
  - MEC's Statement of Committee Organization has a "Connected Organization's Name" field for continuing committees (PACs), on scanned filings (`mec.mo.gov/Scanned/PDF/...`); check whether the committee search pages show it as text
  - FEC committee data (`connected_organization_name`) for PACs that are also federally registered; the `fec` loader already talks to that API
  - FollowTheMoney (now part of OpenSecrets) codes state contributors by industry; check whether its API or downloads are still offered and on what terms

## Low priority
- [ ] Listing of companies that operate in the official's jurisdiction, highlight which ones have donated. Source options:
  - Secretary of State business entity registry: no bulk export (only UCC bulk data, by agreement). Request an extract under the Sunshine Law (template in docs/sunshine_requests.md)
  - Missouri Accountability Portal (mapyourtaxes.mo.gov) data downloads: state expenditures by vendor per fiscal year, pipe-delimited. Covers companies paid by the state, with vendor names
  - EPA Facility Registry Service or OSHA establishment data: named, geocoded sites for regulated industries only
  - Census County Business Patterns: counts by industry, no company names
- [ ] Save a copy of the literal Sunshine Law (RSMo Chapter 610, sections 610.010-610.035, from revisor.mo.gov) in the repo, along with the other sections docs/sunshine_requests.md cites (105.483-105.492, Court Operating Rule 2), noting the date each was retrieved
- [ ] Each January: add the year's rates to the `federal_salaries` seed (senate.gov, uscourts.gov)
- [] write a simplified summary of the missouri sunshine act
