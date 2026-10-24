# Sources

One section per loader: what the source is, what lands, and the quirks found so far. Each has a
flow diagram (SVG, rendered from the `.puml` next to it) in [diagrams/sources](diagrams/sources). Raw tables land under `data/raw/<table>/`.
How a bill moves between the two chambers, which the `mo_house` and `mo_senate` records follow, is in
[diagrams/mo_bill_flow.svg](diagrams/mo_bill_flow.svg).

## Summary

| Loader | Source | Data it provides | Coverage | Gate |
|---|---|---|---|---|
| `mo_house` | Missouri House (documents.house.mo.gov) | members, bills, per-member roll-call votes | `MOGOV_LOOKBACK_YEARS` (default 10; PDFs from 2014) | |
| `mo_senate` | Missouri Senate journals (senate.mo.gov) | per-senator roll-call votes | `MOGOV_LOOKBACK_YEARS` | |
| `mo_senate_topics` | Missouri Senate topical index (senate.mo.gov) | Senate bills, subject terms for Senate bills and House bills that reached the Senate | `MOGOV_LOOKBACK_YEARS` (regular sessions) | |
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
| `epa_frs` | EPA Facility Registry Service | regulated facilities (name, address, coordinates, NAICS, owner) placed in districts; businesses in each official's district that donated to them | current state file (refreshed every few months) | |
| `census_zcta` | Census Bureau Gazetteer | ZIP code area centers and land areas (find-by-ZIP) | newest vintage | |

## mo_house: Missouri House of Representatives

Flow: [diagrams/sources/mo_house.svg](diagrams/sources/mo_house.svg)

documents.house.mo.gov XML exports (members, bills, actions) plus one PDF per roll call. The PDFs are
the only per-member House vote record.

- Lands: `mo_house_members`, `mo_house_bills`, `mo_house_lists`, `mo_house_rollcalls`,
  `mo_house_rollcall_votes`.
- Window: `MOGOV_LOOKBACK_YEARS` (default 10). Roll-call PDFs go back to 2014.
- Shard units: session codes (XML) and session days (roll-call PDFs).

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
  `fct_vote_bills` links House votes to bills exactly. Roll calls the XML doesn't nest (all House votes on
  Senate bills, some on House bills) are linked by the lead bill of the measure printed on the PDF
  (`matched_by = 'measure text'`). In October 2026 5,274 of 6,449 roll calls were linked; most of the rest
  are procedural (approve journal, quorum calls, rules, previous question).
- Bill sponsors list senators (conferees, handlers) with district 200 + their senate district.
- The bill XML only links roll calls nested under a House bill. It misses House votes on Senate bills
  (third reading, conference reports) and procedural votes ("APPROVE JOURNAL", "QUORUM", "PQ"). Until
  October 2026 the loader found PDFs only through the XML: 3,873 roll calls, 108 of them on Senate
  measures. There is no index of the PDFs, but they are numbered per session day
  (`billsYYS/rollcalls/{day}.{nnn}.pdf`), and a missing number answers with the site's HTML error page,
  like unknown session codes. The loader now probes each day from roll call 1 until the first miss past
  the highest number the XML links, for days 1 to the last linked day + 3 (10 days for a session the XML
  links none in). That found 6,449 roll calls, 1,526 on Senate measures. Misses are cached for good once
  the session's year is over and re-checked daily before that. The first probe took about 8 minutes per
  shard with 4 shards.
- PDF text extraction is cached by PDF content (`data/cache/pdftext/`). Before that, a re-run spent
  3–10 minutes per shard re-parsing PDFs that were already downloaded.

## mo_senate: Missouri Senate journals

Flow: [diagrams/sources/mo_senate.svg](diagrams/sources/mo_senate.svg)

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
- Some votes have an "Excused from voting—Senator Hegeman—1" line (recorded as `not voting`).
- Some journals print a section's total before its names ("Absent with leave—Senators—2 Eigel
  Gannon"). A section's names therefore also end at the next section heading. Before October 2026 they
  ran on into it, picking up "Vacancies", "NAYS" or "Absent" as senators and filing the next section's
  senators under the wrong vote.
- Names are space-separated, so a two-word surname looks like two senators. Known ones are listed in
  `COMPOUND_SURNAMES` (Holly Thompson Rehder, printed "Thompson Rehder"); dbt matches a two-word token on
  its last word. The PDF text sometimes cuts "Senator" short ("Senato"); such words are skipped.
- The `assert_votes_within_seats` dbt test fails if a vote lists more than 34 senators. It caught all of
  the above: 443 votes listed 35 or 36 names before the fixes.
- PDF parsing (about 3 s per journal) dominates a cold run, so it shards well. The extracted text is
  cached by PDF content, so re-runs skip it.

## mo_senate_topics: Missouri Senate topical index

Flow: [diagrams/sources/mo_senate_topics.svg](diagrams/sources/mo_senate_topics.svg)

senate.mo.gov's "Topical Index" (`/BillTracking/bills/keywords?year=YYYY&session=R`) lists every bill of a
regular session under each subject keyword. It covers all Senate bills and resolutions, plus the House bills
that reached the Senate. The keywords are the legislature's shared subject index. The House XML only carries
subjects from 2024, so this fills in earlier sessions. It also adds Senate bills to `fct_bills`, which lets
`fct_vote_bills` link Senate votes on Senate bills.

- Lands: `mo_senate_bill_topics`, one row per (session, keyword, bill card): keyword, bill label, link,
  description and sponsors, as the page prints them.
- Window: `MOGOV_LOOKBACK_YEARS`. Shard units: session years (one page each, 3–6 MB).

Quirks:
- The page title "TOPICAL INDEX" uses the same heading markup as the keywords. It has no bill cards, so it
  lands nothing.
- Extraordinary sessions (`session=E`) have no index; the page comes back empty.
- Two terms are spelled differently from the House index: "Elementary and Secondary Education, Department
  of" (House: "…, DEPT. OF") and "Workers' Compensation" (House: no apostrophe). Staging maps them to the
  House spelling.
- The Senate indexes House bills a little differently from the House: for the 486 House bills in both
  (2024–26), 1,576 of the Senate's 2,807 terms match the House's 2,092. A House bill keeps the House's own
  terms where it has them (`fct_bill_subjects.subject_source`).
- A House bill that never reached the Senate has no Senate entry, so House bills before 2024 that died in
  the House still have no subjects.
- The House export doesn't name its roll calls on Senate bills, so House votes on Senate bills aren't
  linked to a bill.

## mec: Missouri Ethics Commission (opt-in)

Flow: [diagrams/sources/mec.svg](diagrams/sources/mec.svg)

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
- Committee donors on CD1_A carry only a name (`committee`); `mecid` is the receiving committee. To go
  one hop back (who funds the PAC that funds an official, #9), `int_mec__donor_committees` matches that name
  to the names committees file under, in tiers: a MECID typed into the name, the same name (case,
  punctuation and spacing ignored), a normalized name (MO = Missouri, Assn = Association, ...), and a core
  name without words like PAC, Political, Action, Committee, Fund, Account (also tried on the name outside
  parentheses, and on a filer's parenthesized short name). A match counts only if that committee was active within a year
  of the gift, and only when it is unique. Measured October 2026 over both feeds ($489M from committees):
  68% of the dollars match one committee, 1.4% are ambiguous, 30% match nothing. An exact name match alone
  got about 46%. Most of the misses are federal and out-of-state PACs (DRIVE, AFSCME, DGA), which don't
  file with MEC, plus acronyms (HRCC, AMECPAC) that no name rule can expand. Distinct committees can differ
  only by "MO" vs "Missouri" ("MO Values PAC" and "Missouri Values PAC"), so the exact-name tier is tried
  first.
- Personal financial disclosures (PFDs) are not online. MEC's 2026 Ethics Guide: "State law requires a
  request to receive copies of PFDs filed with the Commission. Therefore, PFDs are not available for
  public viewing on the MEC's website." Anyone can request copies from MEC (legislators, statewide
  officials, candidates). Judges file theirs with the Missouri Supreme Court instead.

## tap_mec: MEC via The Accountability Project

Flow: [diagrams/sources/tap_mec.svg](diagrams/sources/tap_mec.svg)

Cleaned MEC contributions, expenditures and lobbyist expenditures from TAP's public S3 mirror.

- Lands: `tap_mec_contributions`, `tap_mec_expenditures`, `tap_mec_lobbyist_expenditures`.

Quirks:
- Coverage ends in 2022.
- Column names are TAP's, not MEC's.
- Some rows are malformed, so they're read with `ignore_errors` and without strict mode. The quote and
  escape characters are set explicitly: with non-strict sniffing, DuckDB mis-read some quoted fields
  and silently merged the rows after them (about 900 rows lost before October 2026).
- The contributions mirror combines two MEC layouts. The second (contribution years 2020-2022) has no
  `ctrb_name` / `ctrb_type`: a committee donor is named in `committee`, an organization in `company`, a
  person in first/last name, and absent parts are blank strings, not nulls. Until October 2026 staging lost
  the donor's name and type on about 40,000 such rows ($93M), which showed as "(unnamed)" (#30).
- About 10,000 contribution rows name the donor with one character (`C`, `~`, `0`), mostly individuals
  itemized by federal committees transferred to MEC; the real name is in first/last name (#31).
- A few MECIDs are lower-case (`c000525`); the intermediate models upper-case them.
- A committee-to-committee gift names the donor committee only. `cmte_id` / `mecid` is the receiving
  committee's ID, and there is no donor MECID. The same holds for MEC's direct export (see mec below).

## fec: Federal Election Commission

Flow: [diagrams/sources/fec.svg](diagrams/sources/fec.svg)

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

Flow: [diagrams/sources/voteview.svg](diagrams/sources/voteview.svg)

- Lands: `voteview_members`, `voteview_rollcalls`, `voteview_votes`.
- Window: `MOGOV_VOTEVIEW_CONGRESSES`.
- Full-chamber files; Missouri members are picked out in dbt.

## house_fd: U.S. House financial disclosures

Flow: [diagrams/sources/house_fd.svg](diagrams/sources/house_fd.svg)

Yearly national index plus each Missouri filing's PDF, split into text lines.

- Lands: `house_fd_index`, `house_fd_pdf_lines`.
- Shard units: index years and PDF URLs.

Quirks:
- Scanned paper filings (DocID 8xxxxxxx/9xxxxxxx) have no text layer. They land as one
  `has_text = false` row, so the gap is visible.
- Periodic transaction reports live under `ptr-pdfs/`; everything else is under `financial-pdfs/`.

## senate_efd: U.S. Senate eFD (opt-in)

Flow: [diagrams/sources/senate_efd.svg](diagrams/sources/senate_efd.svg)

- Lands: `senate_efd_filings`, `senate_efd_rows`.
- Enable with `MOGOV_ACCEPT_SENATE_EFD_TERMS=1`, which accepts the use statement (5 U.S.C. app.
  105(c)) on your behalf.

Quirks:
- Requests are CSRF-protected, so the loader accepts the use statement and then searches.
- Paper filings are page images: they're recorded with `is_paper = true` and not parsed.
- Report pages aren't cached.

## courtlistener_bulk: judges and judicial disclosures

Flow: [diagrams/sources/courtlistener_bulk.svg](diagrams/sources/courtlistener_bulk.svg)

Quarterly Postgres CSV exports from CourtListener's public S3 bucket: people, positions, courts,
schools, and federal judges' financial disclosures.

- Lands: `cl_*` tables.

Quirks:
- The exports are Postgres CSV with backslash-escaped quotes (`\"`), not doubled ones, so the reader is
  told `escape='\'`. Left to sniffing, DuckDB dropped rows, and the reimbursements file looked like an
  unbalanced quote and ran out of memory. With the explicit dialect it lands all 33,472 rows.
- Missouri filtering (mo, moctapp*, moed, mowd, ca8) happens in dbt.
- Disclosure line items from scanned AO-10 reports are OCR text. Most of it is readable with typos
  ("State of Missoun"), but about 1% of non-investment items are noise, such as `SIE = RE`,
  `5. - Ie — ~~ Fe) 7 _ il`, or a form's value-code legend read as an item. Staging flags these as
  `is_garbled` (macro `mogov.is_garbled_text`). The rule: more than half of the letters and digits fall
  outside 3+ letter words (or `&` names like AT&T), or there's no run of 4 letters and no `&` name.
  Flagged items stay in `fct_disclosures` but are kept out of `fct_commercial_ties` and `fct_family_ties`. Investments are never flagged, because their
  tickers and fund codes would read as garbled. A sanity test fails if more than 5% of items get flagged.

## courtlistener_case_bulk: case history from bulk files

Flow: [diagrams/sources/courtlistener_case_bulk.svg](diagrams/sources/courtlistener_case_bulk.svg)

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

Flow: [diagrams/sources/courtlistener_cases.svg](diagrams/sources/courtlistener_cases.svg)

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

Flow: [diagrams/sources/bluebook.svg](diagrams/sources/bluebook.svg)

Chapter PDFs (executive, legislative, judicial), one row per text line.

- Lands: `bluebook_lines`.
- Window: `MOGOV_BLUEBOOK_EDITIONS`.

Quirks:
- PDF file names differ between editions. Links are scraped from the edition page, with a fallback to
  the 2019+ naming scheme.
- Pages mix one- and two-column layouts. A page counts as two-column when almost no words cross the
  midline.
- In the judicial chapter's alphabetical judge index, the page header can land on the same line as the
  first entry ("Alphabetical list of Missouri Judges Brewer, Craig D. ...", 2025-2026 p. 123). The header
  is stripped before parsing (#41).
- Names in the index can use a typographic apostrophe (`O’Hara`). It is normalized to `'`. Before October
  2026 those entries were dropped (#42).

## openstates_people: Open States

Flow: [diagrams/sources/openstates_people.svg](diagrams/sources/openstates_people.svg)

- Lands: `openstates_people` (each `data/mo/**/*.yml` file) and `openstates_current_csv`.

Quirks:
- The flat CSV carries Wikidata QIDs that the YAML often lacks.

## congress_legislators: unitedstates/congress-legislators

Flow: [diagrams/sources/congress_legislators.svg](diagrams/sources/congress_legislators.svg)

- Lands: `congress_legislators_current`, `congress_legislators_historical`. Only people with any
  Missouri term are kept.
- These records hold the cross-IDs: bioguide, FEC, ICPSR (Voteview), OpenSecrets, Vote Smart, Wikidata.

## fjc_judges: Federal Judicial Center

Flow: [diagrams/sources/fjc_judges.svg](diagrams/sources/fjc_judges.svg)

- Lands: `fjc_judges`, one wide row per Article III judge since 1789. Column names are kept as
  published.

## wikidata: positions, occupations, relatives

Flow: [diagrams/sources/wikidata.svg](diagrams/sources/wikidata.svg)

- Lands: `wikidata_positions`, `wikidata_attributes`, `wikidata_relatives`,
  `wikidata_own_leadership`, `wikidata_mo_officeholders`.
- Shard units: QIDs. Shard 0 also lands the discovery query.

Quirks:
- It needs `MOGOV_CONTACT`: Wikimedia refuses User-Agents without contact info.
- QIDs come from Open States, congress-legislators, and a discovery query for living holders of
  Missouri positions. It reads those loaders' raw files, so it is a stage-2 loader. As a stage-1 loader
  its shards raced `openstates_people` and failed on a missing `openstates_current_csv`.


## shor_mccarty: state legislator ideology

Flow: [diagrams/sources/shor_mccarty.svg](diagrams/sources/shor_mccarty.svg)

- Lands: `shor_mccarty`. Harvard Dataverse, January 2025 release covering 1993–2022, with wide per-year
  columns. License CC BY-NC-SA 4.0.

## census_tiger: district and place boundaries

Flow: [diagrams/sources/census_tiger.svg](diagrams/sources/census_tiger.svg)

Census Bureau TIGER/Line shapefiles: state senate (SLDU) and house (SLDL) districts, congressional
districts, counties and places. They feed `dim_district` and `fct_official_districts`, the "find my
officials" lookup. Judicial circuits are groups of counties; the county→circuit table comes from the
Official Manual (`int_bluebook__county_circuits`). Court of Appeals districts (RSMo 477.050–.070) and
federal judicial districts (28 U.S.C. 105) are also groups of counties, fixed by statute, so they come from
the `mo_county_courts` seed.

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
- In October 2026, seven state judges had no circuit in `dim_official`, so they had no district rows. The
  cause was in the Official Manual's judge index, not TIGER: the dot leader can run straight into the circuit
  ("Associate ..............35th"). `int_judges__state_index` now accepts that, which also recovered six
  judges whose index line had failed to parse at all.

## census_zcta: ZIP code areas

Flow: [diagrams/sources/census_zcta.svg](diagrams/sources/census_zcta.svg)

Census Bureau Gazetteer file for ZIP Code Tabulation Areas: each ZCTA's internal point (a point inside the
area, near its center) and land and water area. It feeds `dim_zcta` and the frontend's "find my officials by
ZIP" lookup, which runs in the browser: the district at the internal point is the answer, and districts
within a circle of the ZIP's land area are listed as "may also reach".

- Lands: `census_zcta_gazetteer`, the national file verbatim (about 33,000 rows, all columns as text, names
  lower-cased); `dim_zcta` keeps Missouri's ZIP prefixes 630-658.
- Shard units: one, the national file.

Quirks:
- The delimiter changed: older Gazetteer files are tab-separated, the 2026 file is pipe-separated
  (`GEOID|GEOIDFQ|ALAND|...`). The loader lets DuckDB sniff it instead of fixing one.
- ZCTAs approximate USPS ZIP codes from census blocks; PO-box-only ZIPs have no ZCTA, so the page says the
  ZIP isn't found and points to location or the map.
- A ZIP can cross district lines (65101, Jefferson City, touches two Senate and four House districts), which
  is why the page shows the other districts it may reach instead of a single answer.

## mo_employee_pay: Missouri state payroll

Flow: [diagrams/sources/mo_employee_pay.svg](diagrams/sources/mo_employee_pay.svg)

data.mo.gov's "<year> State Employee Pay" datasets (the Missouri Accountability Portal's employee data):
calendar-year gross pay per employee, agency and position title. Legislators, statewide officials and
state judges are on it; `fct_salaries` picks them out. Federal officials aren't on it. Their pay is fixed by
statute and not published per person, so `fct_salaries` adds the office's annual salary from the
`federal_salaries` seed (`pay_basis = 'statutory salary'`). Add that year's rates to the seed each January.

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

## epa_frs: EPA Facility Registry Service

Flow: [diagrams/sources/epa_frs.svg](diagrams/sources/epa_frs.svg)

EPA's Facility Registry Service (FRS) lists every site an EPA or state environmental program regulates:
factories, fuel stations, quarries, auto body shops, dry cleaners, utilities, farms with permits, landfills.
Each site has a name, street address, coordinates, NAICS industry codes and the organizations that own or
operate it. dbt places each site in the districts, counties and cities that contain it
(`fct_district_facilities`), then lists the businesses in each district-elected official's area and flags
those that gave to the official (`fct_jurisdiction_businesses`).

It is the only free, named and geocoded list of businesses found for Missouri. The Secretary of State's
business registry has no bulk export, the Missouri Accountability Portal's vendor payments have no address
(see Quirks), and Census County Business Patterns has counts but no names. FRS covers regulated sites only, so
offices, shops and most service businesses are missing.

- Lands: `epa_frs_facilities`, `epa_frs_organizations`, `epa_frs_naics`, `epa_frs_sic`, one row per CSV row of
  `MO_FACILITY_FILE.CSV`, `MO_ORGANIZATION_FILE.CSV`, `MO_NAICS_FILE.CSV` and `MO_SIC_FILE.CSV` from the Missouri state file
  (`https://ordsext.epa.gov/FLA/www3/state_files/state_combined_mo.zip`, about 35 MB). The payload is the row
  as a JSON object keyed by the CSV header.
- Shard units: the four CSV files. The zip is downloaded once and shared.
- Districts: point-in-polygon of the facility's coordinates against the current `dim_district` boundaries.
  The geometry functions are dispatched per backend (`macros/compat/spatial.sql`); on DuckDB they need the
  `spatial` extension, which `dbt/profiles.yml` loads (downloaded on first use).
- Donor match, two ways (`matched_by`):
  - `same name`: the donor organization's name equals the facility's, owner's or parent company's after
    normalizing case and punctuation and dropping a leading "the" and legal-form words (Inc, LLC, Co,
    Corp...).
  - `same company`: both names carry one brand from the `company_brands` seed. Corporate money mostly comes
    from PACs named after the brand ("Ameren Missouri PAC", "Spire PAC", "AT&T Missouri Employee PAC"), while
    sites are filed under legal or subsidiary names ("UNION ELECTRIC CO", "LACLEDE GAS", "SOUTHWESTERN BELL
    TELEPHONE", "KANSAS CITY POWER & LIGHT"). The seed covers the largest corporate donors with Missouri sites.
  - In October 2026: 502 (official, facility) pairs by name and 1,541 more by brand, for 122 officials.
- Each matched site also carries the matched donors' first and last contribution year, the receiving
  committee's filing page (`contributions_url`) and `match_confidence` (`medium` when any of that money was tied
  to the official by name only).
- Industry: the primary NAICS code when a site has one (31% of the geocoded sites in October 2026). Otherwise
  the site's SIC code (1987 Standard Industrial Classification, from `MO_SIC_FILE.CSV`; a primary code before an
  unknown or secondary one) is mapped to a NAICS sector through the `sic_naics_sectors` seed, a hand-written
  table from SIC major group (two digits, longer where a group splits across sectors) to NAICS sector. That gives
  a sector, not a NAICS code: `int_epa_frs__facilities.naics_code` then holds the two-digit sector prefix and
  `naics_source` is `sic`. Together they cover 56% of the geocoded sites; the rest have neither code.
- `rpt_district_business_industries` counts each official's sites by NAICS sector (`naics_sectors` seed, from
  the primary NAICS code's first two digits). The profile page ships only the donor sites plus these counts: a
  U.S. House district holds up to ~10,500 sites, too many for the per-official JSON budget.

Quirks:
- A few rows fuse two records onto one line (a closing quote is missing: `...,"O"110015893693",...`). DuckDB's
  CSV reader, even with `ignore_errors`, dropped 35 good organization rows after each such line, so the
  loader reads the files with Python's csv module. The two malformed rows per file land with their values
  under `_fields` and drop out in staging.
- About a third of the sites (36k of 112k in October 2026) have no coordinates and so no district. 54 have
  coordinates outside Missouri.
- Most sites carry no NAICS code (149k of 218k (official, site) rows in October 2026), so the largest
  per-sector group is usually "No industry code".
- Organization types are mostly `UNKNOWN`, so government sites are also recognized by name ("City of ...",
  "... County", "... School District", "Public Works") as well as by a government org type or federal agency.
- One owner per facility is kept: owner/operator, then owner, operator, permittee, preferring a known org
  type.
- Branded fuel stations carry the brand in their name but are mostly independently owned ("BILL S PHILLIPS
  66"), so oil brands are not in `company_brands`.
- Missouri Accountability Portal (mapyourtaxes.mo.gov, also the "State Expenditures" datasets on data.mo.gov)
  was checked for the same purpose and not used: its files have agency, category, vendor name (cut at 30
  characters) and amount per fiscal year, with no vendor address, and include employees' reimbursements.
