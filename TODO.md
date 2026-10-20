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
- [ ] `fct_vote_bills`: House roll calls on combined bills (`HCS HBs 267 & 347`, `SS SCS SBs 49 & 118`) link only the lead bill. Link every bill number in the measure if bill-level reports need the others

## Low priority
- [ ] Add a defense industry (Boeing, General Dynamics, Northrop Grumman, RTX are large federal donors) to `interest_keywords` and `industry_subjects`
- [ ] Listing of companies that operate in the official's jurisdiction, highlighting the ones that donated. Source options:
  - Secretary of State business entity registry: no bulk export. Request an extract under the Sunshine Law (template in docs/sunshine_requests.md)
  - Missouri Accountability Portal (mapyourtaxes.mo.gov) downloads: state payments by vendor per fiscal year, pipe-delimited
  - EPA Facility Registry Service or OSHA establishment data: named, geocoded sites for regulated industries only
  - Census County Business Patterns: counts by industry, no company names
- [ ] Write a simplified summary of the Missouri Sunshine Law (full text in docs/reference/rsmo_chapter_610_sunshine_law.md): what's open, what can be closed, how to request records, deadlines, fees and remedies
- [ ] Each January: add the year's rates to the `federal_salaries` seed (senate.gov, uscourts.gov)
