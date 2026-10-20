# TODO List

## High priority

## Medium priority
- [ ] Send the Sunshine Law requests for personal financial disclosures (templates in docs/sunshine_requests.md): MEC for legislators, statewide officials and candidates; the Clerk of the Supreme Court for judges. Fill in the project description and contact, build the filer lists from `dim_official`, log the dates sent. Load the copies that come back through a seed or a local-folder loader
- [ ] Bill subjects for pre-2024 House bills that never reached the Senate. The House XML has no `SubjectIndex` before 2024 and the House site no longer serves older subject indexes. Candidate sources:
  - LegiScan: free API key (30,000 queries/month), weekly per-state datasets with bills, subjects, sponsors and roll calls. Check the license and Missouri's coverage years
  - Open States bulk session CSVs: Missouri 2017-2026, free login; check whether they carry subjects
- [ ] Widen `interest_keywords` coverage (49% of organization contributions and lobbyist gifts by amount, October 2026; `docs/interest_keywords.md` has the sources and evidence for what is confirmed, deliberately unclassified, or still unknown). Largest still unknown: Missouri Justice PAC ($880k, one contribution; St. Joseph, MEC C190952), Paladin PAC (Wright City), CN-MO PAC (235 E High St Ste 301, Jefferson City), POL PAC, Shamrock PAC, The Rowdy PAC, WPG PAC (Columbia), Nexus PAC (714 Locust St, St. Louis), FCA PAC (Chesterfield), MCR PAC, Catalyst PAC, Real Action PAC (Clayton), MOCS Action (a 501(c)(4) granted in 2026). Most look like lobbyist or leadership PACs: Real Action and Another Viceroy PAC share treasurer Henry Elster's Clayton office, and Catalyst PAC looks like the Catalyst government-affairs firm. Add a keyword only once its sponsor is confirmed. Already tried (October 2026):
  - MEC's committee page `mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=...` (MECIDs are in `stg_mec__contributions_made`): every PAC above lists no connected organization and no officers
  - Matching each PAC's address in the raw `mec_cd1_a` contributor rows against association offices: this is what confirmed MHA, MBWA and DIG; the PACs above sit at consultant or home addresses
  - Next step, needs the user: FollowTheMoney's API is still offered, free with a myFollowTheMoney account, and its data is CC BY-NC-SA 3.0. Its contributor industry codes could classify the rest. Create the account and put the key in `.env`

## Low priority
- [ ] Listing of companies that operate in the official's jurisdiction, highlighting the ones that donated. Source options:
  - Secretary of State business entity registry: no bulk export. Request an extract under the Sunshine Law (template in docs/sunshine_requests.md)
  - Missouri Accountability Portal (mapyourtaxes.mo.gov) downloads: state payments by vendor per fiscal year, pipe-delimited
  - EPA Facility Registry Service or OSHA establishment data: named, geocoded sites for regulated industries only
  - Census County Business Patterns: counts by industry, no company names
