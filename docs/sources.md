# Sources

One section per loader: what the source is, what lands, and the quirks found so far. Each has a
flow diagram in [diagrams/sources](diagrams/sources). Raw tables land under `data/raw/<table>/`.

## Summary

| Loader | Source | Data it provides | Coverage | Gate |
|---|---|---|---|---|
| `mo_house` | Missouri House (documents.house.mo.gov) | members, bills, per-member roll-call votes | `MOGOV_LOOKBACK_YEARS` (default 10; PDFs from 2014) | |
| `mo_senate` | Missouri Senate journals (senate.mo.gov) | per-senator roll-call votes | `MOGOV_LOOKBACK_YEARS` | |
| `mec` | Missouri Ethics Commission | state campaign contributions and spending, candidate↔committee links, lobbyist gifts | 2023+ | opt-in |
| `tap_mec` | MEC via The Accountability Project | state campaign finance and lobbyist gifts | 2011–2022 (gifts from 2004) | |
| `fec` | Federal Election Commission | federal candidates, committees, PAC contributions, donor aggregates | `MOGOV_FEC_CYCLES` | API key for aggregates |
| `voteview` | Voteview | Congress roll calls, votes, DW-NOMINATE ideology | `MOGOV_VOTEVIEW_CONGRESSES` | |
| `house_fd` | U.S. House Clerk | House members' financial disclosures and trades | 2015+ | |
| `senate_efd` | U.S. Senate eFD | senators' financial disclosures | as filed | opt-in |
| `courtlistener_bulk` | CourtListener bulk files | judges, positions, education, federal judges' disclosures | quarterly snapshot | |
| `courtlistener_case_bulk` | CourtListener bulk files | Missouri state and federal court dockets and opinions | quarterly snapshot | |
| `courtlistener_cases` | CourtListener API | recent cases and outcomes for judges and lawyers | ~125 requests/day | token for outcomes |
| `bluebook` | Missouri Official Manual | biographies, judges, county→judicial circuit table | `MOGOV_BLUEBOOK_EDITIONS` | |
| `openstates_people` | Open States | state legislators, executives, mayors: roles, party, ids | current + retired | |
| `congress_legislators` | unitedstates/congress-legislators | Missouri members of Congress, cross-system ids | all Missouri terms | |
| `fjc_judges` | Federal Judicial Center | Article III judges' careers | since 1789 | |
| `wikidata` | Wikidata | past offices, occupations, employers, relatives and the organizations they lead | as edited | `MOGOV_CONTACT` |
| `shor_mccarty` | Harvard Dataverse | state legislator ideology scores | 1993–2022 | |
| `mo_employee_pay` | data.mo.gov State Employee Pay | yearly gross pay of legislators, statewide officials and state judges | `MOGOV_LOOKBACK_YEARS` (published from 2007) | |
| `census_tiger` | Census Bureau TIGER/Line | legislative and congressional district, county and city boundaries | newest vintage | |

## mo_house: Missouri House of Representatives

documents.house.mo.gov XML exports (members, bills, actions) plus one PDF per roll call. The PDFs are
the only per-member House vote record.

- Lands: `mo_house_members`, `mo_house_bills`, `mo_house_lists`, `mo_house_rollcalls`,
  `mo_house_rollcall_votes`.
- Window: `MOGOV_LOOKBACK_YEARS` (default 10). Roll-call PDFs go back to 2014.
- Shard units: session codes (XML) and roll-call PDF URLs.

Quirks:
- Session codes are two-digit year plus type: `1` regular, `2`–`4` extraordinary. Unknown codes return
  HTTP 200 with an HTML page, not a 404. The loader probes all four types per year and treats HTML as
  "no such session".
- The open session has no zip yet, so the loader walks the list files and fetches per-member and
  per-bill XML.
- Vote tokens are printed surnames, sometimes with a district ("SMITH 46"), plus "MR SPEAKER".
  Some names are truncated ("FOUNTAIN HENDERS"). dbt matches them to members
  (`int_mo_house__member_identity`, seed `house_speakers`).
- The site asks clients not to poll its XML more than every 30 minutes. Cached copies keep it well
  under that.
- Every shard reads every session zip to list the roll calls. In the October 2026 full run, two shards
  fetched the same zip at once and the second rename of the cache file failed on Windows
  (`PermissionError: [WinError 5]`), failing both shards. The HTTP cache now lets one process download a
  URL while the others wait for its copy, and retries the rename.
- Bill XML carries the House subject index (`SubjectIndex`) only from the 2024 sessions on, so earlier
  bills have no subjects in `fct_bill_subjects`. Older sessions would need another source (Open States'
  bills API needs a key).
- Each bill's roll calls are nested under the bill text version voted on
  (`BillText[].RollCalls[].RollCall[].RollCallPDF`). The PDF URL is the House `vote_id`, so
  `fct_vote_bills` links House votes to bills exactly. About 80% of roll calls belong to a bill; the
  rest are motions and resolutions.
- Bill sponsors list senators (conferees, handlers) with district 200 + their senate district.
- PDF text extraction is cached by PDF content (`data/cache/pdftext/`). Before that, a re-run spent
  3–10 minutes per shard re-parsing PDFs that were already downloaded.

## mo_senate: Missouri Senate journals

The daily journal PDFs are the only per-senator roll-call record.

- Lands: `mo_senate_journals`, `mo_senate_votes`.
- Window: `MOGOV_LOOKBACK_YEARS`.
- Shard units: journal PDF URLs.

Quirks:
- A vote is a text block: `YEAS—Senators … —N  NAYS—… Absent—… Absent with leave—… Vacancies—…`.
  The dashes can be em, en or hyphen.
- Senators who share a surname are suffixed "(16)" (2025+) or "(16th Dist.)" (earlier). Both are
  normalised to "(16)".
- Running page headers ("Journal of the Senate 118", day lines) appear mid-block and are stripped.
- The block regex is bounded at 2,500 characters, so a block missing its "Vacancies" line can't
  swallow the rest of the journal.
- PDF parsing (about 3 s per journal) dominates a cold run, so it shards well. The extracted text is
  cached by PDF content, so re-runs skip it.

## mec: Missouri Ethics Commission (opt-in)

Direct exports from mec.mo.gov: itemized contributions/expenditures (CD1_A, CD3_B, CD3_C, summary),
the candidate↔committee crosswalk per election, and lobbyist expenditures.

- Lands: `mec_cd1_a`, `mec_cd3_b`, `mec_cd3_c`, `mec_summary`, `mec_candidate_committees`,
  `mec_lobbyist_expenditures`.
- Enable with `MOGOV_MEC_OPT_IN=1`. robots.txt disallows these pages and Imperva bot protection rejects
  non-browser User-Agents (`MOGOV_MEC_USER_AGENT`).
- Shard units: (report type, year), crosswalk years, the lobbyist export.

Quirks:
- ASP.NET WebForms: each postback must carry the `__VIEWSTATE` of the page it came from. An export
  answers with a file, not a page. Posting from the export body used to lose the view state, so MEC
  silently returned its generic page. Every election after the first in a year then landed the site
  footer (14 junk rows) instead of candidates. Fixed in October 2026: the form keeps the last real page.
- The exports quote every field, and names can contain apostrophes (`"'Together With Schaper'"`).
  DuckDB's non-strict sniffing mis-read such fields and silently merged the following rows, losing about
  2,800 rows across 2023–26 (contributions, expenditures, report summaries). The loader now sets
  `quote` and `escape` explicitly.
- Elections with no candidates return the search page instead of a table. These are logged as
  `mec.crosswalk_empty`.
- The election search only goes back to 2020: in October 2026 its year dropdown offered 2020–2034.
  Asking for 2016 or 2018 returned no election dates (`mec.crosswalk_no_elections` on every run).
  The default `MOGOV_MEC_CROSSWALK_YEARS` now starts at 2020. Years the dropdown doesn't offer are
  skipped and logged as `mec.crosswalk_year_not_offered`. Those years never returned rows, so nothing
  was lost, but committees first registered for a pre-2020 election are only linked to an official if
  they also filed for a later one. An offered year with no dates is still logged as
  `mec.crosswalk_no_elections` and not cached.
- MEC answers in under a second (the lobbyist search takes about 13 s). The fixed `MOGOV_MEC_PAUSE`
  (3 s) between requests is most of the runtime. A cold run is about 4 requests per export year and
  3 per election date.
- Personal financial disclosures (PFDs) are not online. MEC's 2026 Ethics Guide: "State law requires a
  request to receive copies of PFDs filed with the Commission. Therefore, PFDs are not available for
  public viewing on the MEC's website." Anyone can request copies from MEC (legislators, statewide
  officials, candidates). Judges file theirs with the Missouri Supreme Court instead.

## tap_mec: MEC via The Accountability Project

Cleaned MEC contributions, expenditures and lobbyist expenditures from TAP's public S3 mirror.

- Lands: `tap_mec_contributions`, `tap_mec_expenditures`, `tap_mec_lobbyist_expenditures`.

Quirks:
- Coverage ends in 2022.
- Column names are TAP's, not MEC's.
- Some rows are malformed, so they're read with `ignore_errors` and without strict mode. The quote and
  escape characters are set explicitly: with non-strict sniffing, DuckDB mis-read some quoted fields
  and silently merged the rows after them (about 900 rows lost before October 2026).

## fec: Federal Election Commission

Bulk files (candidates, committees, links, committee→candidate contributions, candidate totals) plus
API lookups for leadership PACs and donor aggregates.

- Lands: `fec_candidates`, `fec_committees`, `fec_cand_cmte_links`,
  `fec_committee_contribs_to_candidates`, `fec_candidate_summary`, `fec_sponsored_committees`,
  `fec_receipt_aggregates` (needs a real `FEC_API_KEY`), `fec_individual_contribs`
  (`MOGOV_FEC_INDIV=1`).
- Window: `MOGOV_FEC_CYCLES`.
- Shard units: (file, cycle) and FEC candidate IDs.

Quirks:
- The files are pipe-delimited with no header row. Headers come from the published dictionaries,
  except `weball`, whose columns are hard-coded from the FEC docs.
- Fields contain bare quotes, so quoting and escaping are disabled.
- Data is landed nationally and filtered to Missouri in dbt.
- `DEMO_KEY` allows about 10 calls per hour. Sponsor lookups are cached for 30 days, so even the demo
  key eventually covers everyone.

## voteview: Congress roll calls and DW-NOMINATE

- Lands: `voteview_members`, `voteview_rollcalls`, `voteview_votes`.
- Window: `MOGOV_VOTEVIEW_CONGRESSES`.
- Full-chamber files; Missouri members are picked out in dbt.

## house_fd: U.S. House financial disclosures

Yearly national index plus each Missouri filing's PDF, split into text lines.

- Lands: `house_fd_index`, `house_fd_pdf_lines`.
- Shard units: index years and PDF URLs.

Quirks:
- Scanned paper filings (DocID 8xxxxxxx/9xxxxxxx) have no text layer. They land as one
  `has_text = false` row, so the gap is visible.
- Periodic transaction reports live under `ptr-pdfs/`; everything else is under `financial-pdfs/`.

## senate_efd: U.S. Senate eFD (opt-in)

- Lands: `senate_efd_filings`, `senate_efd_rows`.
- Enable with `MOGOV_ACCEPT_SENATE_EFD_TERMS=1`, which accepts the use statement (5 U.S.C. app.
  105(c)) on your behalf.

Quirks:
- Requests are CSRF-protected, so the loader accepts the use statement and then searches.
- Paper filings are page images: they're recorded with `is_paper = true` and not parsed.
- Report pages aren't cached.

## courtlistener_bulk: judges and judicial disclosures

Quarterly Postgres CSV exports from CourtListener's public S3 bucket: people, positions, courts,
schools, and federal judges' financial disclosures.

- Lands: `cl_*` tables.

Quirks:
- The exports are Postgres CSV with backslash-escaped quotes (`\"`), not doubled ones, so the reader is
  told `escape='\'`. Left to sniffing, DuckDB dropped rows, and the reimbursements file looked like an
  unbalanced quote and ran out of memory. With the explicit dialect it lands all 33,472 rows.
- Missouri filtering (mo, moctapp*, moed, mowd, ca8) happens in dbt.

## courtlistener_case_bulk: case history from bulk files

The quarterly bulk dockets, opinion clusters and opinion panels, filtered to Missouri state and federal
courts (mo, moctapp*, moed, mowd, ca8). They feed `fct_case_history` through
`int_courtlistener__bulk_case_matches` (dbt var `cl_case_bulk`, set automatically once the tables
exist).

- Lands: `cl_mo_dockets`, `cl_mo_opinion_clusters`, `cl_mo_cluster_panel`.
- One shard unit, because each file is filtered by the ids kept from the previous one.

Quirks:
- The national files are huge: dockets about 5.1 GB and clusters about 2.5 GB compressed (2026-09
  snapshot). This is the one loader that filters before landing. Kept records are copied byte for byte.
- DuckDB can't read bz2, so Python splits the records. A record ends at a newline once its running
  count of double quotes is even.
- Clusters have no court column; they're kept by `docket_id`.
- Panels (judge person ids) are sparse for state courts. dbt therefore also matches the judge's surname
  as a whole word in the `judges` text, but only in courts the judge sits on.
- Surnames repeat on the same court across generations: a 1910 Judge Smith on the 8th Circuit, fathers
  and sons on the Court of Appeals. Judges-text matches therefore count only from the judge's first
  known judicial start date; with no start date, only panel matches count. Attorney matches start at
  dbt var `case_history_min_year` (default 1975).
- In the 2026-09 snapshot, 8th Circuit (ca8) opinions stop in August 2019. The API loader covers later
  ones.
- The filtered CSVs are cached per snapshot (`data/cache/courtlistener/mo-*.csv`), so re-runs within
  a quarter are quick. Cases can be up to three months stale; `courtlistener_cases` tops up.

## courtlistener_cases: case history (stage 2)

Searches CourtListener's opinions for each official who is or was a judge or lawyer
(`marts.fct_legal_careers`).

- Lands: `cl_cases`.
- Shard units: officials.

Quirks:
- It needs a first dbt build, which is why it's stage 2.
- Tokens are capped at about 125 requests per day across all endpoints. On a long `Retry-After` the
  loader continues from cache only, and the next run resumes. If the quota is already spent when the run
  starts and nothing is cached yet, `cl_cases` lands 0 rows (seen in the October 2026 runs:
  `cases.quota_exhausted` with `retry_after_s` about 16 hours). Run it again the next day.
- Without a token it can only search (5 requests per minute) and gets no dispositions.
- CourtListener has no trial-court (circuit) cases, and Case.net forbids automated access.
- It's now a top-up for `courtlistener_case_bulk`. Where both have a case, an API row with outcome data
  wins.

## bluebook: Missouri Official Manual

Chapter PDFs (executive, legislative, judicial), one row per text line.

- Lands: `bluebook_lines`.
- Window: `MOGOV_BLUEBOOK_EDITIONS`.

Quirks:
- PDF file names differ between editions. Links are scraped from the edition page, with a fallback to
  the 2019+ naming scheme.
- Pages mix one- and two-column layouts. A page counts as two-column when almost no words cross the
  midline.

## openstates_people: Open States

- Lands: `openstates_people` (each `data/mo/**/*.yml` file) and `openstates_current_csv`.

Quirks:
- The flat CSV carries Wikidata QIDs that the YAML often lacks.

## congress_legislators: unitedstates/congress-legislators

- Lands: `congress_legislators_current`, `congress_legislators_historical`. Only people with any
  Missouri term are kept.
- These records hold the cross-IDs: bioguide, FEC, ICPSR (Voteview), OpenSecrets, Vote Smart, Wikidata.

## fjc_judges: Federal Judicial Center

- Lands: `fjc_judges`, one wide row per Article III judge since 1789. Column names are kept as
  published.

## wikidata: positions, occupations, relatives

- Lands: `wikidata_positions`, `wikidata_attributes`, `wikidata_relatives`,
  `wikidata_own_leadership`, `wikidata_mo_officeholders`.
- Shard units: QIDs. Shard 0 also lands the discovery query.

Quirks:
- It needs `MOGOV_CONTACT`: Wikimedia refuses User-Agents without contact info.
- QIDs come from Open States, congress-legislators, and a discovery query for living holders of
  Missouri positions. It reads those loaders' raw files, so it is a stage-2 loader. As a stage-1 loader
  its shards raced `openstates_people` and failed on a missing `openstates_current_csv`.


## shor_mccarty: state legislator ideology

- Lands: `shor_mccarty`. Harvard Dataverse, January 2025 release covering 1993–2022, with wide per-year
  columns. License CC BY-NC-SA 4.0.

## census_tiger: district and place boundaries

Census Bureau TIGER/Line shapefiles: state senate (SLDU) and house (SLDL) districts, congressional
districts, counties and places. They feed `dim_district` and `fct_official_districts`, the "find my
officials" lookup. Judicial circuits are groups of counties; the county→circuit table comes from the
Official Manual (`int_bluebook__county_circuits`).

- Lands: `census_tiger_features`, one row per feature: the attribute table verbatim (`properties`), the
  geometry as GeoJSON (lon/lat, NAD83) and the layer, vintage and file.
- Shard units: file kinds (`29_sldl.zip`, `29_cd119.zip`, `us_county.zip`...).

Quirks:
- Each layer comes from the newest TIGER year that has it. In October 2026, `TIGER2026/SLDL` listed
  `tl_2026_29_sldl.zip` but served a short HTML page for it. The loader checks every download is a zip and
  falls back to the previous vintage (`census_tiger.not_a_zip`).
- Missouri redrew its congressional map in 2025. TIGER2026 has only the 120th Congress's districts
  (`cd120`), but today's members represent the 119th's. The loader lands the newest file for every Congress
  it finds in the last three vintages; `dim_district.is_current` marks the Congress in session.
- Counties exist only as a national file (about 80 MB). Only its Missouri features (STATEFP 29) are
  landed.
- TIGER names St. Louis city and St. Louis County both "St. Louis"; `NAMELSAD` ("St. Louis city", "St.
  Louis County") tells them apart, and the circuit match uses it.
- Seven state judges have no circuit in `dim_official` (October 2026), so they have no district rows.

## mo_employee_pay: Missouri state payroll

data.mo.gov's "<year> State Employee Pay" datasets (the Missouri Accountability Portal's employee data):
calendar-year gross pay per employee, agency and position title. Legislators, statewide officials and
state judges are on it; `fct_salaries` picks them out.

- Lands: `mo_employee_pay`, verbatim CSV (all columns text). Only the agencies that employ officials are
  fetched (Legislature, Judiciary and the six statewide offices), staff included.
- Window: `MOGOV_LOOKBACK_YEARS`. Shard units: calendar years (one dataset each; ids from the Socrata
  catalog).

Quirks:
- Gross pay is everything paid in the year, not the base salary. Someone who changed office mid-year has
  one row per position (the 2025 governor also has a Lieutenant Governor row).
- Officeholder titles (`STATE REPRESENTATIVE`, `SENATOR`, `SENATE FLOOR LEADER`, `CIRCUIT JUDGE`,
  `GOVERNOR`...) are listed in the seed `mo_payroll_office_titles`. Staff titles such as "SENATORS' STAFF"
  never count. Add a title to the seed if the payroll renames a position.
- Names are legal names, "LAST, FIRST M": "LUETKEMEYER, ANTON H" is Tony Luetkemeyer, and "BLACK, JAMES R"
  is Rusty Black. Legislators are therefore matched by surname, chamber and year against the seat history,
  when exactly one member fits. Others are matched by name. In October 2026, 2025 pay matched 147 of 155
  representatives and 32 of 33 senators; the rest share a surname with a colleague and use a nickname.
- The current year's dataset appears in January of the following year.
- Federal officials (Congress, federal judges) are paid by the U.S. and are not in this source.
