# Sources

One section per loader: what the source is, what lands, and the quirks found so far. Each has a
flow diagram in [diagrams/sources](diagrams/sources). Raw tables land under `data/raw/<table>/`.

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
- PDF parsing (about 3 s per journal) dominates this loader's runtime, so it shards well.

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
- Elections with no candidates return the search page instead of a table. These are logged as
  `mec.crosswalk_empty`.
- MEC answers in under a second (the lobbyist search takes about 13 s). The fixed `MOGOV_MEC_PAUSE`
  (3 s) between requests is most of the runtime. A cold run is about 4 requests per export year and
  3 per election date.
- Personal financial disclosures are not online; they're released only on Sunshine Law request.

## tap_mec: MEC via The Accountability Project

Cleaned MEC contributions, expenditures and lobbyist expenditures from TAP's public S3 mirror.

- Lands: `tap_mec_contributions`, `tap_mec_expenditures`, `tap_mec_lobbyist_expenditures`.

Quirks:
- Coverage ends in 2022.
- Column names are TAP's, not MEC's.
- Some rows are malformed, so they're read with `ignore_errors` and without strict mode.

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
- `financial-disclosures-reimbursements` is skipped. The 2026-09 export has an unbalanced quote that
  swallows the rest of the file, and DuckDB runs out of memory.
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
  loader continues from cache only, and the next run resumes.
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
  Missouri positions. Run those loaders first.

## acu_ratings: American Conservative Union

- Lands: `acu_ratings`. One query to an undocumented GraphQL API (plain http).
- This is one interest group's scorecard, not a neutral measure.

## shor_mccarty: state legislator ideology

- Lands: `shor_mccarty`. Harvard Dataverse, January 2025 release covering 1993–2022, with wide per-year
  columns. License CC BY-NC-SA 4.0.
