# TODO List

## High priority

## Medium priority
- [ ] Send the Sunshine Law requests for personal financial disclosures (templates in docs/sunshine_requests.md): MEC for legislators, statewide officials and candidates; the Clerk of the Supreme Court for judges. Fill in the project description and contact, build the filer lists from `dim_official`, log the dates sent. Load the copies that come back through a seed or a local-folder loader
- [ ] Bill subjects for pre-2024 House bills that never reached the Senate. The House XML has no `SubjectIndex` before 2024 and the House site no longer serves older subject indexes. Candidate sources:
  - LegiScan: free API key (30,000 queries/month), weekly per-state datasets with bills, subjects, sponsors and roll calls. Check the license and Missouri's coverage years
  - Open States bulk session CSVs: Missouri 2017-2026, free login; check whether they carry subjects
- [ ] Widen `interest_keywords` coverage (44% of organization contributions and lobbyist gifts by amount, October 2026). Largest unclassified: Missouri Justice PAC, Paladin PAC, CN-MO PAC, A Better Missouri PAC, MHA PAC (not the hospital association; its PAC is HEALTHPAC), Living Well PAC, RQC PAC, HBS MO State PAC, the MBA region PACs, Dealers Interested in Government. Many are leadership or lobbyist pass-through PACs with no single industry. Add a keyword only once its sponsor is confirmed. Where to look:
  - MEC's Statement of Committee Organization ("Connected Organization's Name" field), on scanned filings at `mec.mo.gov/Scanned/PDF/...`
  - FEC committee data (`connected_organization_name`) for federally registered PACs; the `fec` loader already uses that API
  - FollowTheMoney (now part of OpenSecrets) industry codes for state contributors; check whether its API or downloads are still offered

## Low priority
- [ ] Listing of companies that operate in the official's jurisdiction, highlighting the ones that donated. Source options:
  - Secretary of State business entity registry: no bulk export. Request an extract under the Sunshine Law (template in docs/sunshine_requests.md)
  - Missouri Accountability Portal (mapyourtaxes.mo.gov) downloads: state payments by vendor per fiscal year, pipe-delimited
  - EPA Facility Registry Service or OSHA establishment data: named, geocoded sites for regulated industries only
  - Census County Business Patterns: counts by industry, no company names
