# TODO List

## High priority
- [ ] Senate votes that match no senator (`int_mo_senate__votes.person_key` null): Wallingford (1,106 tokens, 2017-2020) and Kehoe (663, 2017-2018) never match, and no senator matches on the January 4-10, 2017 votes. Their seats seem to be missing from `int_mo_legislators__seats` (former senators, or terms starting after the first day of session). Find the gap in the Open States people data and fill it (seed or another source)

## Medium priority
- [ ] `fct_vote_bills`: House roll calls on combined bills (`HCS HBs 267 & 347`, `SS SCS SBs 49 & 118`) link only the lead bill. Link every bill number in the measure if bill-level reports need the others
- [ ] Send the Sunshine Law requests for personal financial disclosures (templates and requirements in docs/sunshine_requests.md): MEC for legislators, statewide officials and candidates; the Clerk of the Supreme Court for judges. Fill in the project description and contact, build the filer lists from `dim_official`, then log the dates sent. Once copies arrive, add them through a seed or a local-folder loader
- [ ] Bill subjects for pre-2024 House bills that never reached the Senate (the House XML has no `SubjectIndex` before 2024, and the House site's subject index keeps only a few years: 2017-2024 return nothing, the static `sbjndx` archive stops at 2011). Candidates:
  - LegiScan: free API key (30,000 queries/month), weekly per-state datasets (JSON/CSV) with bills, subjects, sponsors and roll calls. Check the license terms and Missouri's coverage years before building a loader
  - Open States bulk session CSVs: Missouri 2017-2026, free account login required; check whether they carry subjects
- [ ] Widen `interest_keywords` coverage: classified names cover 44% of organization contributions and lobbyist gifts by amount (October 2026, up from 41% after adding AGC, AMEC, MEDA, HEALTHPAC, MOSFA, CHIPP and Cheyenne International). Largest still unclassified: "NONE" (a data-quality placeholder, $1.27M), Missouri Justice PAC, Paladin PAC, CN-MO PAC, A Better Missouri PAC, MHA PAC (not the hospital association, whose PAC is HEALTHPAC), Living Well PAC, RQC PAC, HBS MO State PAC, the MBA region PACs, Dealers Interested in Government. Many are leadership or lobbyist pass-through PACs with no single industry. Federal donors are often companies (Boeing, General Dynamics, Northrop Grumman, RTX) that need a defense industry, which `industry_subjects` doesn't have. Sources to look up whom they represent:
  - MEC's Statement of Committee Organization has a "Connected Organization's Name" field for continuing committees (PACs), on scanned filings (`mec.mo.gov/Scanned/PDF/...`); check whether the committee search pages show it as text
  - FEC committee data (`connected_organization_name`) for PACs that are also federally registered; the `fec` loader already talks to that API
  - FollowTheMoney (now part of OpenSecrets) codes state contributors by industry; check whether its API or downloads are still offered and on what terms

## Low priority
- [ ] Listing of companies that operate in the official's jurisdiction, highlight which ones have donated. Source options:
  - Secretary of State business entity registry: no bulk export (only UCC bulk data, by agreement). Request an extract under the Sunshine Law (template in docs/sunshine_requests.md)
  - Missouri Accountability Portal (mapyourtaxes.mo.gov) data downloads: state expenditures by vendor per fiscal year, pipe-delimited. Covers companies paid by the state, with vendor names
  - EPA Facility Registry Service or OSHA establishment data: named, geocoded sites for regulated industries only
  - Census County Business Patterns: counts by industry, no company names
- [ ] Each January: add the year's rates to the `federal_salaries` seed (senate.gov, uscourts.gov)
- [ ] Write a simplified summary of the Missouri Sunshine Law (RSMo Chapter 610; full text in docs/reference/rsmo_chapter_610_sunshine_law.md): what's open, what can be closed, how to request records, deadlines, fees and remedies
