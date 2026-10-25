# Office metrics: candidate sources by office type

Research for issue #40. Checked 2026-10-25 against the primary pages cited. Nothing here is loaded yet.
Every ranking idea rests on one sourced, measured number, with no composite scores
(docs/frontend_principles.md). Law enforcement (sheriffs, prosecutors, police, MSHP) is #178.
Bills and statutes are #34/#175/#241/#243. Personal financial disclosures are #1.

Probing was polite: a handful of requests per site, with the project User-Agent. Sites that returned
403 to automated clients were not worked around (see "Blocked or unverified").

## What we already land but do not model

These need dbt work only, no new loader. (Judge dockets are under "Federal judges" below.)

| Data | Where it sits | What it enables |
|---|---|---|
| House committee membership and positions (Chair, Vice-Chair, Co-Chair, Ranking Minority Member, Member) | `mo_house_lists` (`COMMITTEELIST`: memberships only for sessions 231, 241, 251, 253, 254, i.e. 2023+) and `mo_house_members` (`CommitteePosition`: positions 2017+, every session except 253) | Committee assignments per member and session |
| House sponsored and co-sponsored bills per member | `mo_house_members` (`RepresentativeLegislation`), `fct_bill_sponsors` | Bills sponsored, share that passed. `fct_bills` has no outcome column (`last_action` null for 18,578 of 24,215), so derive it from House XML actions (`Action` in 16,784 of 16,787 payloads); depends on #34. Senate sponsors barely resolve (13 of 958 with `official_id`): effectively House-only |
| `cl_retention_events` | CourtListener bulk | Empty in our export (0 rows); not usable |

## State representatives and senators

| Candidate | Measures | Coverage | Access | Single number for a ranking |
|---|---|---|---|---|
| Senate committee hearing cover pages | Per-senator PRESENT/ABSENT at each committee hearing | 2026 verified; earlier years via `year=` not verified | HTML index per committee, one PDF per hearing (`Committees/Reports/IndexReports?handler=HearingCoverReport&year=2026&coverId=17`). No terms stated | Committee hearing attendance % (hearings present / hearings held, per senator and session) |
| Senate committee bill votes | Per-senator YES/NO/ABSENT/ABSTAIN on "do pass" in executive session | Same | Same pattern (`handler=BillVoteReport&voteId=399`) | Committee votes missed % |
| House committee hearings | Upcoming hearings only (`UpcomingHearingList.xml`) | Current day forward | XML | Not usable: no attendance or committee votes found |
| State expenditures (data.mo.gov) | Payments by the state to named payees, including legislators' `LEGISLATIVE DAILY EXPENSE ALLOWANCE` (per diem) and `IN-STATE MILEAGE` under agency `LEGISLATURE` | One dataset per fiscal year, 2000 to 2026 | Socrata API (JSON/CSV), no key needed for light use. No licence field on the datasets; state data policy: https://mo.gov/data-policy | Per diem dollars claimed per legislator per fiscal year; mileage dollars (context only, driven by distance) |
| Census ACS (district demographics) | Population, income and so on per legislative district | ACS 5-year, annual | Census API, free key (a keyless request returned "Missing Key") | Context only; no ranking |

FY2023 `LEGISLATURE` (dataset `k3n5-mge9`, 107,523 rows, `rowsUpdatedAt` 2024-09-26): 240 per diem rows totalling $1.80M and 295 mileage rows totalling $880,139.52. A row is one payee's annual total for that detail line (240 distinct payees), not one payment.
Payees are person names ("ADAMS, JOSEPH L"), so the join to officials is by name key.

Not worth adding: Open Meetings (`au6r-w9n3`, 131 rows of upcoming state-body notices, no attendance).

## Statewide executives

| Candidate | Measures | Coverage | Access | Single number |
|---|---|---|---|---|
| State Auditor reports | Audit of an office or agency with a four-level rating (Excellent, Good, Fair, Poor) and findings | Site offers 1999 to 2026, but unfiltered `SearchAudits` returns exactly 1,000 rows (2018-08-29 to 2026-10-23); older years need filters or paging. `citz_sum_fk` is null for most reports (57 of 91 in 2026). Rating scale since 2011 | JSON list `auditor.mo.gov/AuditReport/SearchAudits`; per-audit PDF citizens summary `CitzSummaryDirect?id=` | Rating of the latest audit of the official's office, or number of findings. Ratings cover audited areas only, per the Auditor's own legend |
| State expenditures (data.mo.gov) | Payments to vendors by agency (`OFFICE OF GOVERNOR`, `OFFICE OF STATE AUDITOR` and so on) | 2000 to 2026 | Socrata | Dollars paid by an official's agency to a vendor who also donated. Co-occurrence, not causation |
| Executive orders (SoS) | EOs by year, 1980 to 2026 | Yearly pages under `sos.mo.gov/library/reference/orders/` | HTML; search tool "undergoing maintenance" | Skipped: a count of orders says nothing about quality |
| Vetoes | Governor's vetoes and overrides | Only news stories and a Legislative Library list found | none verified | Derive from bill actions once #241/#243 land |
| AG opinions and lawsuits | | The ago.mo.gov opinions URL tried returned 404 | none verified | Skipped; lawsuit counts are not a neutral measure |
| Treasurer investment reports | | not checked in depth | | Skipped; no per-official measured number |

State Auditor rating text: the rating sentence is plain text via pdfplumber ("In the areas audited, the overall
performance of this entity was Good/Fair."). Checked in the 2018 Scott County report (citz 676, Good), Secretary of
State 2024-007 (citz 987, Fair) and Treasurer 2026-086 (citz 1083, Good). Do not attach a county audit rating to an
individual county official: the summary says it does not indicate any one official's performance.

## State judges

| Candidate | Measures | Coverage | Access | Single number |
|---|---|---|---|---|
| SoS official election returns (retention) | Yes/No votes on retaining Supreme Court and Court of Appeals judges | Official returns PDFs back to Feb 2012; 1996 to 2011 on a separate page | PDF with clean text ("Renée" extracts cleanly with pdfplumber), e.g. `CMSImages/ElectionResultsStatistics/2024GeneralElection.pdf` (36 pages) | Retention "Yes" share. 2024: Broniec 63.1%, Gooch 62.2% |
| Judicial Performance Review (Missouri Bar, yourmissourijudges.org) | Committee finding "meets standards", lawyer survey 1 to 5 | 2014 to 2024 in news coverage | Site describes the process; no scores found on the page I could read | Unverified: need the per-judge report format |
| Courts.mo.gov annual statistics (Judicial Report, Circuit Court Profiles, Supplement) | Cases filed, disposed and pending per circuit and county; appellate counts | Reports since 1997 (profiles and supplements since 2000) | Blocked: 403 to WebFetch, connection failure to curl | Cases disposed / cases filed per circuit (clearance rate), per circuit not per judge |
| CourtListener state dockets (already landed) | `cl_mo_dockets` for `mo` and `moctapp` has 0 rows with `assigned_to_id`, `date_filed` and `date_terminated` | none | dbt | Not usable for time-to-disposition; see "Federal judges" |

## U.S. House and Senate (MO delegation)

| Candidate | Measures | Coverage | Access | Single number |
|---|---|---|---|---|
| govinfo BILLSTATUS bulk XML | Every federal bill with sponsor `bioguideId`, cosponsors, actions, `laws` (public law number), latest action | 108th (2003) to 119th Congress; 119th modified 2026-10-24 | Bulk zips per congress and bill type, e.g. `BILLSTATUS/119/hr/BILLSTATUS-119-hr.zip` (33 MB); no key. US government work; the page states no licence | Sponsored bills that became law; join by bioguide id (already loaded from `congress_legislators`) |
| Committee membership (congress-legislators) | Committee and subcommittee assignments with rank and title | Current only in `committee-membership-current.yaml`; committees back to 1973 in `committees-historical.yaml`; CC0 | Same GitHub repo we already load | Count of chair / ranking seats held (a count of titles, not a score) |
| House Statement of Disbursements | Per-Member office spending (personnel, travel, supplies), organisation code like `MO05CLE` | Quarterly since 2009 | CSV (detail grid 26 MB per quarter, 133,091 rows for April-June 2026: 123,701 DETAIL, 7,771 SUBTOTAL, 1,619 GRAND TOTAL; summary 0.6 MB) and PDF. No licence stated | Official expenses per Member per year (YTD amount) |
| House Community Project Funding (earmarks) | Member-requested projects: recipient, amount, requesting Members, party | FY2027 verified (consolidated xlsx, 6,692 rows; about 82 rows and $101.45M for Missouri members, see below); archive page for earlier years | XLSX plus PDF per subcommittee | Dollars of earmarks requested per Member that appear in the House bills |
| Voteview (already landed) | Missed votes | | | Attendance is already awarded; nothing new needed |
| Senate SOPR reports | Senator office spending | Not reached: 403 | | Unverified |

Earmark table caveats: the earlier "24 Missouri rows, $32.6M" counted only ", MO" locations. By State/Location alone
there are 70 Missouri rows, $92,901,404. THUD, Interior, Homeland, Energy & Water and MilCon use just "MO" (46 rows,
$60,317,072). Labor-HHS leaves State/Location empty and puts the place in the Project text (12 Missouri-member rows,
$8.55M). Missouri members total about 82 rows and about $101.45M. Join by requestor to member, not by location:
requestor is a surname ("Alford", "Hoyer, Ivey"); members sharing a surname get a state suffix ("Smith (NE)"); and
out-of-state members can request Missouri projects (Schmidt, KS, requested Swope Health in Kansas City).
Amounts are House bill amounts, not enacted amounts.

## Federal judges

| Candidate | Measures | Access | Single number |
|---|---|---|---|
| U.S. Courts Federal Judicial Caseload Statistics | Filings, terminations, median time to disposition per district, yearly since 2001 | uscourts.gov report page | Median months from filing to civil disposition per district (not per judge) |
| FJC Integrated Database | Case-level civil and criminal terminations since 1970 (SAS or tab-delimited) | fjc.gov/research/idb; judge identity not stated | Skipped for now; CourtListener dockets already landed carry `assigned_to_id`, dates and `idb_data_id` |
| CourtListener dockets (already landed; optional input gated by the `cl_case_bulk` var) | `cl_mo_dockets` and `cl_mo_cluster_panel`. Federal district rows: `moed` 81,193 + `mowd` 84,604 = 165,797 rows, 62 judges, with `assigned_to_id`, `date_filed`, `date_terminated`. 812 dockets end before they were filed: filter or flag them rather than test for "no negative durations" | dbt | Median days from filing to termination per judge, with n and share of dockets having both dates |
| Reversal rates | | No bulk source found | Skipped |

## Mayors and local officials

| Candidate | Measures | Access | Note |
|---|---|---|---|
| State Auditor local audits | Audits of counties, cities, courts, schools with the same rating | Same JSON list, category filters | Covered by the Auditor source issue |
| "Show Me Local Government" | Per-county property tax, recent audits, finance reports | `auditor.mo.gov/ShowMeLocalGovernment/CountySelect` | Bulk format not verified |
| Cities' annual financial reports | Filed with the Auditor within six months of fiscal year end | Searchable online per Auditor press releases | No bulk download found |
| Municipal elections | Results | Held by county clerks, no central source | Skipped |

## All elected offices

SoS official returns (PDF with clean text: office, candidate, party, votes, % per race, precincts reported):
margin of victory, uncontested races and turnout. This is the source #28 needs. Precinct-level files are sold
by the Elections Division. Election Night Reporting (`enr.sos.mo.gov`) is a JavaScript page with no download
links; the PDFs are the path. Single numbers: margin of victory in points; years in office (derivable from
`fct_office_history`).

## Blocked or unverified

- courts.mo.gov returned 403 / no connection to automated clients; senate.gov returned 403.
  Terms, formats and cadence are unverified. Not worked around.
- MEC personal financial disclosures are not an online database (an MEC search URL tried returned 404;
  PFDs have been obtained by records request). Stays with #1.
- House committee roll calls and attendance: not found as a structured record on house.mo.gov.

## Source labels

The maintainer approved eight new candidate labels, now in CLAUDE.md: `source: mo_state_expenditures`,
`source: govinfo_billstatus`, `source: house_sod`, `source: house_cpf`, `source: mo_sos_elections`,
`source: mo_auditor`, `source: census_acs`, `source: uscourts_caseload`.

## Existing candidate labels

`source: legiscan`, `source: followthemoney`, `source: osha_ita`, `source: mo_sos_business`: nothing in
these findings changes them. `source: mo_revisor` belongs to #34/#224 and is untouched.

## Follow-up issues

| Issue | Source |
|---|---|
| #280 | Senate committee hearing attendance and committee bill votes |
| #281 | Dbt-only: House committee posts, sponsorship success rate, federal judge time-to-disposition |
| #282 | State Expenditures (data.mo.gov): legislator per diem, mileage, vendor payments |
| #283 | Federal bill sponsorship and outcomes (GovInfo BILLSTATUS) |
| #284 | Federal committee assignments (congress-legislators) |
| #285 | House Statement of Disbursements |
| #286 | House earmarks (Community Project Funding) |
| #287 | SoS election results: margins, uncontested, judicial retention (serves #28) |
| #288 | State Auditor audit reports and ratings |
| #289 | Small ideas: Census ACS, U.S. Courts caseload, Show Me Local Government |
| #290 | needs-user: blocked sites and Judicial Performance Review (each would need a new source label: courts.mo.gov, Missouri Bar JPR, Senate SOPR; maintainer to approve) |
