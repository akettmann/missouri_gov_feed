# TODO List

## High priority

## Medium priority
- [ ] Send the Sunshine Law requests for personal financial disclosures (templates in docs/sunshine_requests.md): MEC for legislators, statewide officials and candidates; the Clerk of the Supreme Court for judges. Fill in the project description and contact, build the filer lists from `dim_official`, log the dates sent. Load the copies that come back through a seed or a local-folder loader
- [ ] Bill subjects for pre-2024 House bills that never reached the Senate. The House XML has no `SubjectIndex` before 2024 and the House site no longer serves older subject indexes. Candidate sources:
  - LegiScan: free API key (30,000 queries/month), weekly per-state datasets with bills, subjects, sponsors and roll calls. Datasets are CC BY 4.0; the Missouri dataset page lists 2021-2026 sessions (older ones may be under the full history). Its bill pages refuse automated fetches (403), so whether it has subjects for House-only bills before 2024 can only be checked with a key. Needs the user to register for the key
  - Open States: its Missouri scraper takes subjects from the same two places we already use (the Senate topical index and the House XML `SubjectIndex`), so current data adds nothing. Session CSVs scraped years ago might still carry subjects if the House served them then. The CSVs need a free login
  - Wayback Machine copies of the House's old subject index pages on house.mo.gov: free, no key. Not checked yet: the Internet Archive was offline on 2026-10-20
- [ ] Widen `interest_keywords` coverage (49% of organization contributions and lobbyist gifts by amount, October 2026; `docs/interest_keywords.md` has the sources and evidence for what is confirmed, deliberately unclassified, or still unknown). Largest still unknown: Missouri Justice PAC ($880k, one contribution; St. Joseph, MEC C190952), Paladin PAC (Wright City), CN-MO PAC (235 E High St Ste 301, Jefferson City), POL PAC, Shamrock PAC, The Rowdy PAC, WPG PAC (Columbia), Nexus PAC (714 Locust St, St. Louis), FCA PAC (Chesterfield), MCR PAC, Catalyst PAC, Real Action PAC (Clayton), MOCS Action (a 501(c)(4) granted in 2026). Most look like lobbyist or leadership PACs: Real Action PAC (treasurer Henry Elster) and Another Viceroy PAC share a Clayton office, and Catalyst PAC looks like the Catalyst government-affairs firm. Add a keyword only once its sponsor is confirmed. Already tried (October 2026):
  - MEC's committee page `mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=...` (MECIDs are in `stg_mec__contributions_made`): every PAC above lists no connected organization and no officers
  - Matching each PAC's address in the raw `mec_cd1_a` contributor rows against association offices: this is what confirmed MHA, MBWA and DIG; the PACs above sit at consultant or home addresses
  - Next step, needs the user: FollowTheMoney's API is still offered, free with a myFollowTheMoney account, and its data is CC BY-NC-SA 3.0. Its contributor industry codes could classify the rest. Create the account and put the key in `.env`

## Low priority
- [ ] Widen `fct_jurisdiction_businesses` beyond EPA-regulated sites (the `epa_frs` loader, October 2026). Offices, shops and most service businesses are missing. Options:
  - Secretary of State business entity registry: no bulk export. Request an extract under the Sunshine Law (template in docs/sunshine_requests.md). Needs the user to send it
  - OSHA establishment data (inspections, injury reports): named, addressed sites, mostly the same regulated industries
  - Ruled out: the Missouri Accountability Portal's vendor payments have no vendor address; Census County Business Patterns has no company names
