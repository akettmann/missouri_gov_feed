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
| `mo_revisor` | Missouri Revisor of Statutes (revisor.mo.gov) | statute text (RSMo) by section version, repeals and transfers, which bills enacted, amended or repealed each section | current statutes; repeals since 1945 | slow: ~1 request/s |
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
| `mo_sos_elections` | Missouri Secretary of State official returns | race results, margins, uncontested races, judicial retention votes | general and primary elections, Aug 2012 on | |
| `mo_state_expenditures` | data.mo.gov State Expenditures | what each state agency paid each payee per fiscal year: legislators' per diem and mileage, payments to vendors | `MOGOV_LOOKBACK_YEARS` (fiscal years; published from 2000) | |
| `census_tiger` | Census Bureau TIGER/Line | legislative and congressional district, county and city boundaries | newest vintage | |
| `epa_frs` | EPA Facility Registry Service | regulated facilities (name, address, coordinates, NAICS, owner) placed in districts; businesses in each official's district that donated to them | current state file (refreshed every few months) | |
| `mo_auditor` | Missouri State Auditor (auditor.mo.gov) | audit reports of state offices and agencies, counties, cities, courts and schools, with the Auditor's four-level performance rating | reports 1999 to now; ratings from 2012 | |
| `census_zcta` | Census Bureau Gazetteer | ZIP code area centers and land areas (find-by-ZIP) | newest vintage | |

## mo_house: Missouri House of Representatives

Flow: [diagrams/sources/mo_house.svg](diagrams/sources/mo_house.svg)

documents.house.mo.gov XML exports (members, bills, actions) plus one PDF per roll call. The PDFs are
the only per-member House vote record.

- Lands: every `.xml` file of a session zip (and of the open session's walk), whatever its kind, unchanged as
  gzip (`<raw dir>/mo_house_xml/<session>/<FILE>.XML.gz`) with one state row per file in `mo_house_xml_files`
  (kind `member`, `bill`, `list` or `other`; path, source URL, size, sha256, `landed_at` = when this run wrote
  it, not when the House published it), then typed tables parsed from those files by `mogov.parsers.mo_house`:
  `mo_house_xml_bills` with child tables `_bill_actions` (with printed roll-call totals), `_bill_sponsors`,
  `_bill_texts`, `_bill_amendments`, `_bill_rollcalls`, `_bill_subjects`, `_bill_hearings`, `_bill_summaries`,
  `_bill_fiscal_notes` and `_bill_witnesses` (witness-form links only; empty `<Witness/>` elements are not landed); `mo_house_xml_members` with
  `_member_committees` and `_member_counties`; `mo_house_xml_sessions`, `_committees` and `_committee_members`;
  one row per item of the BillList, MemberList, UpcomingHearingList and CalendarList files plus the lists'
  `NOTICE` text (`_list_notices`); and the SenateActList (the House's actions on Senate bills) as
  `mo_house_xml_senate_act_bills` with child tables `mo_house_xml_senate_act_` + `actions`, `texts`, `amendments`,
  `rollcalls`, `hearings`, `summaries`, `fiscal_notes`, `witnesses` (each child row carries a `bill`
  column naming its Senate bill; the list has no sponsor or subject children, the sponsor is on the bill row as
  `sponsor_name`/`sponsor_district`/`sponsor_link`). Bill, text, amendment, summary, fiscal-note and witness-form
  links reach `marts.fct_bill_documents`. The roll-call PDFs land as `mo_house_rollcalls` and
  `mo_house_rollcall_votes`.
- Window: `MOGOV_LOOKBACK_YEARS` (default 10). Roll-call PDFs go back to 2014.
- Shard units: session codes (XML) and session days (roll-call PDFs).

Quirks:
- The member roster can keep listing a member after they left. Rebecca Roeber (member 1790, HD34) died 2019-07-30, yet
  the 2019 veto session (193, September 2019) and all three 2020 sessions (201, 203, 204) still list her, and the
  member XML for 181-204 looks like a stale snapshot (later files do use `vacant_name='Vacant'`). Her House roll-call
  PDFs carry no ROEBER token after about day 38 of session 191, and Open States ends her term 2019-07-30. Rick Roeber
  (member 2215, elected November 2020, expelled April 2021) is the next holder, so HD34 was vacant for all of 2020,
  from 2019-07-30 until January 2021, and the 2020 rows carry no votes. The seat match lands on Rick, so
  `int_mo_house__member_seat_keys` keeps a member id on the person its other sessions matched by given name (only when
  exactly one person matches; member ids with two Open States duplicates keep the seat match), and
  `int_officeholders__years` drops a roster row whose roster member carries an Open States id (the name-anchor
  override assigns it) when that person's last Open States House term ended before the year's January 15 handover,
  so HD34 has no 2020 officeholder. Raw keeps the roster as served. Issue #152.
- The same stale roster also outlives members whose seat match failed, so their row has no Open States id and the
  term test cannot see it. Scott Fitzpatrick (HD158) cast his last vote on 2019-01-09 and became State Treasurer;
  the 2019 roster still lists him though HD158 had no member until Scott Cupps in 2020. Mike Cierpiot (HD30) left for
  the Senate (his last House vote was 2017-09-13) yet the 2018 roster lists him. `int_officeholders__years` therefore
  also drops a roster row when the person's last roll-call vote is before the year's January 15 handover, but only in a year that has House roll calls on or after the handover (each
  January the roster stays whole until that year's roll calls are loaded). Open States
  dates alone are not enough: Lauren Arthur's House term ends 2016-12-31 but she voted through 2018, so her row stays.
  The Speaker must be in the `house_speakers` seed for 2017-2022 as well as 2023+, else a Speaker with no named votes
  (Haahr 2019-2020, Vescovo 2021-2022) would read as a member who stopped voting. Issue #491.
- `bills171/rollcalls/` still holds the 2016 session's roll-call PDFs (numbered by 2016 session day, header
  "98th General Assembly, Second Regular Session"). The probe walks past the last 2017 roll call of a day, so
  it lands them under session 171: 415 roll calls dated 2016 (45 session days, 1/13/2016 to 5/13/2016,
  interleaved with 663 real 2017 ones), none linked from the bill XML. Raw keeps them as served;
  `stg_mo_house__rollcalls` drops roll calls dated outside their session code's year (2016's session, 161, is
  not loaded). Issue #430.
- Other sessions' PDFs also sit in a session's directory (issue #435). `stg_mo_house__rollcalls` checks the header's
  General Assembly and session label against the session code (regular sessions: FIRST in odd years, SECOND in
  even; extraordinary and special sessions: any EXTRAORDINARY or SPECIAL label, since 173 prints SPECIAL, 184
  FIRST EXTRAORDINARY and 174 SECOND EXTRAORDINARY). Dropped: `bills171/rollcalls/002.001`, `002.002` (voting-board test records, Y for the first six names alphabetically or MORRIS+KIDD only; 173 has its own
  different 2.1/2.2), `bills201/rollcalls/012.001` (a copy of 203's), `bills204/rollcalls/003.002`, `003.003`
  (2020-11-19 non-votes: voting-board test/practice records under a regular-session header; HB 2315 was never
  third-read in 201 and "Session Day : 3" is 204's counter). Only a recognised label under the wrong kind of code
  drops a row; an unknown label is kept and fails an accepted_values test. The House also
  publishes some roll calls twice under two file names (261: `003.001`/`003.002`, `004.002`/`004.004`,
  `004.003`/`004.005`, identical content); the file whose name carries the printed roll-call number is kept.
- Voting-board test records survive the header check in 173 and 231 (issue #449): `bills173/rollcalls/002.001`
  (a QUORUM CALL with one voter, HUBRECHT) and `002.002` (a PQ with one voter, LOVE), 2017-05-23, and
  `bills231/rollcalls/026.003`/`026.004` (ADJOURNMENT, 7 and 5 voters, the first names alphabetically, printed after the
  day's last real vote on 2023-02-21). Real roll calls never go below 83 voters of about 162 (a quorum call; a quorum is
  82), so `stg_mo_house__rollcalls` drops a roll call where fewer than a quarter of the listed members cast a vote
  (`house_rollcall_min_participation`; the 204 and 171 test records fall under it as well). The singular test
  `assert_house_rollcalls_quorum_participation` fails on any survivor under half the members unless its URL is in
  `house_rollcall_small_quorum_allowlist` (a genuine call that failed to produce a quorum). Effect: 4 roll calls and 650
  member votes fewer; the 173 attendance of 16 members moves from 80% to 100%, and the House attendance awards for
  2017, 2023 and lifetime shuffle by a rank or a tenth of a point.
- Session 204 has only 5 roll-call PDFs, all "Session Day : 3", and that is complete (issue #449). The only House floor
  vote that session was 2020-11-10 (HB 14 third read and passed; HR 1 was adopted without a roll call); no later House
  action in the bill XML (2020-11-13 to 2020-12-16) is a floor roll call: they are introductions, readings, referrals,
  HR 2's committee hearing and executive session, and the Speaker signing HB 14 and its truly agreed and finally
  passed after Senate passage (which needs no House roll call). The loader probes days up to the last linked day plus 3 (here days 4-6, all the site's 404 page), and
  spot checks of days 7, 8, 10 and 13 also answer 404. Not a loader gap.
- The XML is never converted on the way in: the loader gzips each file as received. The parser reads the
  gzip with lxml (hardened settings in `mogov.xmlparse`) and selects elements by local name, so namespaces,
  attributes, entities and CDATA are the parser's problem, not a regex's. The links that drive crawling
  (`RollCallPDF`, `BillXMLLink`, `RepresentativeXMLLink`) come from the same parsed tree. Re-run the parser
  alone, with no fetching, via `python -m mogov.parsers.mo_house [--shards N --shard I]`.
- Landed but not parsed into rows (only in the gzip): the odd `GRP*` files (e.g. `191-GRP1.XML`: three group
  documents in the shape of a bill that are not House bills; kind `other`, never read by the parser), a member's
  `RepresentativeLegislation` lists (`SponsoredBill`, `CoSponsoredBill`, `SponsoredAmendment`: a per-member view
  of what the bill documents' sponsor and amendment rows already say) and a member's contact details
  (`EmailAddress`, `PhoneNumber`, `CapitolAddress`, `LegislativeAssistant`), which the project keeps out of
  everything but the raw file. Witness forms (which name citizens) are linked, never fetched.
- Coverage: a scan of every cached House XML file (20,327 files, 2016 to 2026) against the paths the parser reads
  finds no other unread element; the scan script lists them by file kind.
- The House BillList lists some bills twice (HR1 and HR2 in the odd-year sessions); the loader fetches and lands
  each linked file once.
- `AmendmentText` is misnamed: it holds the link to the amendment's PDF (`.../bills181/amendpdf/4083H03.02H.pdf`), not text, and is filled on every amendment (8,775 House, 1,023 SenateActList). `MapLink` (the change map) is filled on only a handful, so `stg_mo_house__bill_amendments` stages `amendment_text` as `amendment_url` and `fct_bill_documents` carries both an `amendment` and an `amendment_map` kind.
- The XML lists some amendments twice on the same bill, so `stg_mo_house__bill_amendments` is one row per listing, not per amendment (9,798 rows, 9,686 distinct amendments): 112 pairs (64 in session 251, 2 in 254, 46 in 261). Each pair has adjacent `amendment_index` values and the same `amendment_url`, `lr_number`, `description` and `status`; only `sponsor` differs: a surname with and without its district (83 pairs, "Black" / "Black (137)") or two members who share a surname (29 pairs, "Smith (045)" / "Smith (046)", "Sharp (036)" / "Sharp (037)"). The real key is (`session_code`, `bill`, `amendment_url`). `fct_bill_documents` collapses the pairs (its grain is one row per link). Nothing consumes the amendment sponsor yet; how to resolve it for these pairs is an open policy question (needs-user issue #530), to settle before anything joins amendment sponsor to a legislator or counts amendments by member. `assert_mo_house_amendments_duplicates_are_adjacent_pairs` fails if a duplicate is anything but that adjacent pair.
- `AmendmentSortValue` looks like `0507HH`, so `mo_house_xml_bill_amendments.sort_value` is text. It is filled only from session 241 on (3,275 of 9,798 rows) and only restates `lr_number`: round and amendment number, then the chamber letter and last letter of `lr_number` (`0010H03.04H` is `0304HH`). It disagrees with that reading on 16 rows, all SB1421 in session 261, where it is reordered (`5940S03.01X` is `03XS01`). `stg_mo_house__bill_amendments` does not stage it; the raw column stays. A value that
  does not fit its column type (an integer or date field holding something else) becomes NULL and is logged
  (`mo_house.value_not_integer` / `mo_house.value_not_date`), and a document lxml had to repair is logged as
  `mo_house.xml_recovered` with its file name.
- The raw dir must be writable from the loader: locally `data/raw`, on Cloud Run the mounted bucket named by
  `MOGOV_RAW_DIR`. The gzip files are written atomically and with a fixed header, so a re-run of an unchanged
  file rewrites nothing.
- Empty XML elements are NULL in the typed tables (the old JSON landing held empty strings).
- Session codes are two-digit year plus type: `1` regular, `2`–`4` extraordinary. Unknown codes return
  HTTP 200 with an HTML page, not a 404. The loader probes all four types per year and treats HTML as
  "no such session".
- Session names (`dim_house_session`): the last digit of a code does not say which extraordinary session it is (183 is the 2018 "Special Session", 184 its "1st Extraordinary Session", 253 and 254 the 2025 1st and 2nd). The `SESSIONLIST` file in every session zip carries the House's own names for the whole history, and the frontend labels sessions from it; the open regular session has no zip, so the loader fetches its `SessionList` directly. A session with no name yet shows as "session code NNN".
- The open session has no zip yet, so the loader walks the list files and fetches per-member and
  per-bill XML.
- Vote tokens are printed surnames, sometimes with a district ("SMITH 46"), plus "MR SPEAKER".
  Some names are truncated ("FOUNTAIN HENDERS"). dbt matches them to members
  (`int_mo_house__member_identity`, seed `house_speakers`).
- Tokens do not always spell the roster surname: a compound surname is printed by its last word ("REHDER" is Holly
  Thompson Rehder, "REISCH" is Cheri Toalson Reisch, "COURTWAY" is Cyndi Buchheit-Courtway), a generational suffix is
  dropped ("PRICE" is Wiley Price IV in 2019-2022, Tiffany Price from 2025), and a district is added only while two
  members share a surname ("EVANS 99" / "EVANS 154" until Jean Evans left on 2019-02-05, then a bare "EVANS" is
  David Evans). The roster is an end-of-session list, so a member who left mid-session is missing from their last
  session (Rory Rowland in 2022). `int_mo_house__votes` handles all of these (#539): a whole-surname match beats a
  last-word one, and the Open States seat dates break a tie between same-surname members only when exactly one
  seat covers the vote date.
- A member's seat is matched to an Open States person (district, date and surname; when several same-surname terms overlap, the one whose name starts with the member's given name); when that fails the key is `mohouse:<member id>`.
  Open States also holds some people twice (after a redistricting or a move to the Senate). Both are
  reconciled to one stable `official_id` per person by `int_officials__person_ids` (the same MO House member id, which follows a name change such as Mazzie Boyd/Christensen, member 2381, #151; otherwise the same exact name, or names that differ only in the given
  name like Steve/Steven or Ken/Kenneth (#228, #263), no conflicting seats, and
  either overlapping dated terms in one seat or a chamber move (years alone cannot tell a duplicate record, Kenneth
  Jamison's 2025 stub inside Ken's term, from a successor like Danielle after Dan Smith; dates can, using the dates exactly as Open States gives them: the January-1 adjustment used for year membership would make a January successor overlap a predecessor ending Jan 6-9. Known edge: `int_officials__identity_terms` collapses each (id, year, seat, House member id) to min(start)/max(end), spanning any gap if one id held the seat in two terms in a year); seed `official_id_links` for statewide officers and judges), #97.
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
  (`mo_house_xml_bill_rollcalls`, `parent_kind = 'text'`). The PDF URL is the House `vote_id`, so
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
- Limits of the roll-call probe (issue #538). The probe is bounded by what the XML links, so a House vote the XML
  never mentions can be missed in two ways. (1) Days: it stops at the last day the XML links a roll call for plus
  `DAY_SLACK` (3, `src/mogov/loaders/mo_house.py`). A recorded vote more than 3 session days past the last linked day
  is never requested. For session 204 this does not bite (see above: days 4-6 are all the site's 404 page), but it is a
  structural limit; widening it costs one request per extra empty day per session (a day the XML links nothing
  for has `last_linked = 0`, so `_probe_day` stops at the first miss, roll call 001; a day that does have votes costs
  one request per roll call plus the final miss). Misses are cached for good once the year is over, so re-runs cost
  nothing. It cannot be tested without the network, so it is left as is. (2) Numbers: within a day it
  stops at the first missing number past the highest the XML links for that day, so a gap in the numbering past
  that point hides later roll calls. A session that has XML files but whose XML links no roll call is probed for 10
  days (`DAYS_IF_UNKNOWN`). A session code with no XML files at all gets no `linked` entry and is never probed (unless
  another session's XML links a roll call under its code).
- The XML also links roll-call PDFs the House never published: the fetch returns the HTML error page, and the loader
  keeps the miss in `mo_house_rollcalls` as a row with `error = 'not a pdf'` (60 in October 2026: 201 one, 211 eight,
  221 one, 241 fifty). 55 of them are named under a bill (e.g. `bills241/rollcalls/062.013.pdf`, listed on HB 2634).
  `stg_mo_house__rollcalls` drops error rows, and `fct_vote_bills` now links only roll calls that are in staging, so
  those 55 links are gone (32 bills, 13 of which now have no linked vote; they were dangling `vote_id`s that no
  member vote row carries). A relationships test keeps it that way.
  Those 13 bills have no linked vote in `fct_vote_bills` even though the House recorded one (the XML lists the roll
  call with totals). A bill page, if one is built, could show "roll call recorded, PDF not published" without new loading: the link is in `stg_mo_house__bill_rollcalls` and the miss
  is in the raw `mo_house_rollcalls` rows with `error = 'not a pdf'`. Not built; an open product decision (#570).
- Committee posts (`fct_committee_memberships`, `fct_committee_posts`): the member XML page lists each
  member's committees and subcommittees with a position (Chair, Vice-Chair, Co-Chair, Ranking Minority
  Member, Member), in every session from 2017 except 253, whose pages list none. For 253 the
  `COMMITTEELIST` list (memberships only for 231, 241, 251, 253 and 254) fills in, matched on district.
  `COMMITTEELIST` also lists Senate members (chamber `S`) and a few `N/A` rows; only `H` is used. The
  snapshot is end-of-session. The marts keep former members too (368 people, 14,678 rows; 191 people and 7,939
  rows are not in `dim_official`): `is_current_official` flags who has a profile page, and the frontend ships
  only those. Each row's `source_url` is the House file it came from, taken from `mo_house_xml_files`: the
  session zip for a closed session, the member's own XML file (`.../xml/261-072.xml`) for the open one. A
  file inside a zip has no address of its own. Committee names change between sessions. The metric counts
  full-committee chairs separately from subcommittee chairs.
  The `COMMITTEELIST` lists carry no Co-Chair seats at all (2025 regular session: member pages show 3 co-chair posts the list lacks), and 253's list names fewer committees than 251 or 254 (no Conference Committee on Budget, 22 seats; neither of the two property tax special committees, 40 seats), so 253 shows 617 committee seats against 697 in 251 and 685 in 254. The joint committees are in the list. The profile says so under the 253 row. Re-checked against the typed XML raw (2026-10): no other landed file carries 253 co-chair seats. The 253 member pages have no `Committees` element at all, `UPCOMINGHEARINGLIST` names only a committee's chair, and bill files carry no committee roles. The House does not publish them in the exports, so the gap is accepted and not inferred from 251 or 254 (co-chairs of a joint committee are not guaranteed to carry over); 251 and 254 co-chair posts come from the member pages (3 in 251, 2 in 254).
- Bill sponsorship success (share of a member's sponsored bills that passed) is not built yet: it needs the
  bill status (`fct_bills.status` and `outcome`, from #34), but Senate bills before 2024 have no status (see
  Bill status below), so it can only cover House bills and 2024 and later until #317 lands.
- PDF text extraction is cached by PDF content (`data/cache/pdftext/`). Before that, a re-run spent
  3–10 minutes per shard re-parsing PDFs that were already downloaded.
- Bill status (`fct_bills.status`, `outcome`; `int_bills__status`) comes from each bill's `Action` list. The
  `SenateActList` file adds the Senate bills that reached the House, but only with their House-side and governor
  actions. In 2024 it stops at the speaker's signature for 17 of its 38 bills: 2024 SB 727 was signed into law, yet the list ends at
  "Signed by House Speaker". Such bills get the outcome "no governor action recorded", not "failed". Senate bills
  that never reached the House have no actions in any source we load, so their status is null: 906 of 972 SBs
  and 56 of 58 SJRs in 2026. `SenateActList` exists only for 2024 and later, so every Senate bill of 2017 to
  2023 has a null status and outcome, enacted ones included (2017 to 2023: 0 of 4,143 SBs have a status; 2024: 29
  of 796, none enacted because the list stops before the governor). Counts of failed, pending or enacted bills
  therefore leave out Senate bills, almost all of them before 2024; House bills are complete.
  The same list names the special-session Senate bills (`stg_mo_house__senate_act_bills`, with titles, version, last
  action and effective date), which the Senate topical index never covers: `int_bills__list` adds those the index lacks
  (2025's 253 SB 1, 3 and 4), for `fct_bills` and `fct_vote_bills` alike. Senate bills of older special sessions are still
  missing (#237).
  Quirk: 143 bills (15 to 17 per regular session, 2017 to 2026, none in 2021; e.g. 2024 HB 1 and HB 2) list
  only "Message Received from the Governor, pursuant to Article IV, Section 27" as their action. They are
  re-listings, not new bills: the House repeats the previous regular session's appropriation bills (same bill
  number, bill string and effective date, LR numbers from 241 on; 2024 HB 1 is the FY2024 budget bill of the 2023
  session) only to record the governor's budget/withholding message. Where the previous session is loaded (128 of
  128) the bill string is identical and the original is already "enacted"; the 15 of 2017 repeat the unloaded
  2016 session (161). They get status "relisted for governor message", a null outcome (it is on the original) and
  `relisted_from_session_code` naming the original's session (null for 2017), rather than "introduced" /
  "failed" (#396). Leave them out of per-session bill counts. Loading
  Senate-side actions is #317 (and #237).
- `ActivitySequence` (action order) is only present from 2024. About 1,000 of 138,000 actions are repeated word
  for word under one `Guid` (mostly 2017–2018); staging keeps them once.
- Session codes: 1 is the regular session and 2–4 are special sessions, in order. Code 2 doesn't appear in
  2017–2026: the first special session of a year is 3. 2018's 183 was a legislature-called session with
  resolutions only.

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
- Some votes have an "Excused from voting—Senator Hegeman—1" line. These are Senate Rule 91 recusals by
  members present on the floor ("Pursuant to Senate Rule 91, Senator Washington excused herself from voting
  on ..."), not absences, so they are recorded as `recused` (distinct from `absent with leave`). Only the
  Senate records this; the House PDFs and Voteview do not. Whether a recusal counts as attended is open (#135).
- Some journals print a section's total before its names ("Absent with leave—Senators—2 Eigel
  Gannon"). A section's names therefore also end at the next section heading. Before October 2026 they
  ran on into it, picking up "Vacancies", "NAYS" or "Absent" as senators and filing the next section's
  senators under the wrong vote.
- Names are space-separated, so a two-word surname looks like two senators. Known ones are listed in
  `COMPOUND_SURNAMES` (Holly Thompson Rehder, printed "Thompson Rehder"); dbt matches a two-word token on
  its last word. The PDF text sometimes cuts "Senator" short ("Senato"); such words are skipped.
- The block's closing `Vacancies—None` / `Vacancies—N` lands as `vacancies` on every row of the vote
  (`stg_mo_senate__votes.vacancies`). The `assert_senate_seats_sum_to_34` dbt test (error) checks that senators
  listed + vacancies = 34, with one allow-listed vote: 2021-04-29, HB 574 (`RDay5804291051-1071.pdf` #4), where the
  journal itself prints only 32 names (YEAS 23, NAYS 9) and omits Eigel and Hough. From 2024 the journal prints
  "Excused from voting" after the Vacancies line; the parser's block includes that trailing line (until
  October 2026 it stopped at Vacancies and dropped every 2024+ recusal). `assert_senate_vacancies_parsed`
  fails if `vacancies` is null on every row, i.e. `mo_senate` was never reloaded after the count was added.
- The `assert_votes_within_seats` dbt test fails if a vote lists more than 34 senators. It caught all of
  the above: 443 votes listed 35 or 36 names before the fixes.
- PDF parsing (about 3 s per journal) dominates a cold run, so it shards well. The extracted text is
  cached by PDF content, so re-runs skip it.
- Journal file prefixes: `R` regular, `V` veto, and `S1`/`S2`/`T1`/`T2` extraordinary sessions. The prefix does not
  say which special session it is (2018's `S1` is 183 but its `T1` is 184; 2017's `S1` and `S2` are 173 and 174), so
  `fct_vote_bills` links special-session votes by date, not by prefix. A `source_url` with no `Journals/<prefix>`
  part is treated as a regular `R` journal.
- Special-session Senate bills (SB, SJR, SCR) before 2024 can't be linked to a bill: the Senate act list only
  exists from session 241, so no source lists those bills and a vote on one links to nothing. House bills in
  special sessions link through the House XML actions. From 253 on, Senate bills link through the House XML
  actions (the Senate's own steps are not listed, so the match is by date span).
- The journals also date Open States' Senate seat-terms (`int_mo_legislators__seats`, #516, #522), term by term, so
  every consumer of the seat table (officeholders by year, salary pairing, attendance, peers, sponsors) sees the
  corrected dates. 25 senators in office from 2017 have no Open States start date; the term's first roll-call vote
  stands in as the start. That is the latest the start can be, not the start itself: 23 of the 25 first voted on
  2017-01-04, the journals' first day, so they were seated by then, and the other two first voted later (Jacob
  Hummel 2017-01-10, Bill White 2019-01-09). It agrees with every dated start (first vote on or just after it) and with the 4-year term rule where the rule
  applies; it contradicts the rule for six senators whose Open States term ends 2023-01-04 (two consecutive
  terms). A term Open States ends over a year after its last vote ends at that vote (Ryan Silvey, last vote
  2017-09-13, was listed to 2018-12-31; Will Kraus, 2017-07-25), and a closed term running into the journal years
  with no vote (Joseph Keaveny, Eric Schmitt, Kurt Schaefer, David Pearce) ends the day before the journals begin,
  2017-01-03, the latest it can have ended (the exact date is unknown). Votes are attributed to a senator against
  Open States' own dates (`int_mo_legislators__seats_as_given`), so the correction does not feed back into who a
  vote belongs to.
  Dropping or capping a term for lacking votes only happens when the journals cover it: with no journal loaded, or a
  calendar year of the term with no journal vote (including years after the journals stop, for a closed term), the
  term stays as Open States gives it (#534). Two dbt tests guard
  the attribution these rules trust: `assert_senate_vote_tokens_attributed` (more than 0.05% of vote rows
  unattributed; 0 of 75,677 today) and `assert_senate_terms_have_votes` (a closed Senate term with no attributed
  vote, other than the four who never voted in the journals). The last-vote cap ends Ryan Silvey's term 2017-09-13
  although he was paid into January 2018; whether payroll should override it is open (#551). Mike Cierpiot (SD 8) voted in the House through 2017-09-13, when the Senate seat was vacant
  (Kraus's last vote was 2017-07-25), and first voted in the Senate on 2018-01-08; Open States starts his Senate
  term 2018-01-03. Nothing loaded dates his seating within 2017-09-14 to 2018-01-03 more closely. Only the
  2025-2026 Official Manual is loaded, so it gives no evidence for earlier years.

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

## mo_revisor: Missouri Revisor of Statutes (RSMo)

Flow: [diagrams/sources/mo_revisor.svg](diagrams/sources/mo_revisor.svg)

revisor.mo.gov publishes the Revised Statutes of Missouri as server-rendered pages, with no bulk download. The
table of contents (`Home.aspx`) lists titles and chapters. Each chapter page (`OneChapter.aspx?chapter=N`) lists
its sections in force, one link per section *version* (`bid`). A section page
(`OneSection.aspx?section=S&bid=B`) has the heading, text, effective date and footnotes, starting with the
session-law history ("(RSMo 1939 § 645, A.L. 1957 p. 587, A.L. 2015 S.B. 239)"). One page, `rx.aspx` (~10 MB),
lists every repealed and transferred section with its note and date, so those ~14,700 sections need no page
of their own.

- Lands: `mo_revisor_chapters` (one row per chapter), `mo_revisor_sections` (one row per section version in
  force: the page's content block verbatim, plus its text, effective-date line and footnotes) and
  `mo_revisor_repeals` (one row per repealed or transferred section).
- Shard units: chapters, plus `rx.aspx` (owned by one shard).
- Freshness: the table of contents, chapter lists and `rx.aspx` are re-read weekly. A new enactment or amendment
  is a new version with its own `bid` and URL, so the weekly chapter lists find it. A version's own page only
  changes with annotations, so it is re-read every 180 days.
- dbt: `stg_mo_revisor__*`, then `int_mo_revisor__session_law_bills` (history and repeal notes split into one
  row per bill), then `fct_statute_sections` and `fct_bill_statute_links`.

Quirks:
- **Cross-chamber combined acts.** Five acts join a Senate and a House bill with "&" or "and" ("A.L. 1977 S.B. 111
  & H.B. 130"; 1998 and 2005 use "and"), all before 2017: 1977 SB 111 and HB 130 (6 sections), 1981 HB 519 and SB 16 (1), 1982 SB 649 and HB 1096 (1),
  1998 SB 820 and HB 1587 (1), 2005 HB 353 and SB 254 (2). The section text never names the bill, so the
  combined-act reading (the first bill passed, the other's subject went into it) can't be confirmed from the
  Revisor; it needs the journals. The data argues against it for some: HB 130 (1977) and SB 16 (1981) are the lead
  bill of 53 and 259 other sections, and HB 1096 (1982) leads 5 others. The model still reads these
  as combined (issue #571); `assert_cross_chamber_combined_acts_are_known` pins the five so a new one gets looked at (it warns; add the act to the `known` CTE in that test after a spot-check).
- **Rate limit.** The site blocks an IP address that sends requests less than a second apart several times in
  30 seconds. First it serves a warning page with status 200 in place of the page asked for (the same page it
  serves for a page that doesn't exist). If requests keep coming, every request from that IP, browsers
  included, redirects to `Block.aspx`. Three shards at ~10 requests/s got an IP blocked within two minutes on
  2026-10-25. The block page gives WebMaster@LR.mo.gov for help. All shards and runs on one machine share one
  per-host lock and spacing: requests start at least 2 s apart whatever the shard count, and a warning pauses
  the whole host (see Pacing below).
  Neither page is
  ever cached. A warning backs off 1, 5 and then 15 minutes and retries: at 1.5 s apart, one shard still drew a
  warning after ~600 pages, since other traffic from the same IP counts too. The load stops with `Blocked` on
  a fourth warning or on `Block.aspx`. A cold load reads ~30,500 section-version pages (October 2026), so it
  takes about 17 hours. The first full load finished on 2026-10-26 (exit 0, about 52 minutes on top of the
  pages already cached): 468 chapters, 30,435 section versions and 14,689 repeals; 10 chapters (152, 203, 255,
  280, 312, 318, 342, 460, 560, 564) are empty and were skipped. Nothing lands until a run finishes, but every
  page fetched stays in the HTTP cache (`data/cache`: section pages 180 days, lists 7 days), so re-running reads
  the cached pages without touching the site and continues with the rest.
- **Pacing across shards.** Requests to the host take turns through a lock file and a last-request time in
  `data/cache` (`http.host_throttle`, held across the 2 s wait and the request), so shards and separate runs
  on one machine never send two requests less than 2 s apart; more shards add no speed. (The earlier pacing
  had each shard sleep 2 s × the shard count on its own clock, which let two shards' requests land under a second
  apart, 400 to 520 times an hour with 2 to 4 shards.) A warning page pauses the whole host: the shard that
  got it writes a "pause until" time next to the lock (`.throttle-revisor.mo.gov.pause`) and every shard waits it out (60, 300, then 900 s) before its next request.
  The lock is a file created with `O_EXCL`, which is not a reliable lock on GCS FUSE, where the documented Cloud
  Run setup mounts `/data` (so the cache is shared between tasks, but the lock can't be trusted there). The loader
  therefore refuses to start when `CLOUD_RUN_TASK_COUNT` is above 1: run it as a single task (`--tasks 1`);
  shards (processes) inside that task are fine. A lock older than 900 s is taken for a dead holder's; the slowest
  request, the ~10 MB `rx.aspx`, has to finish inside that.
- A section page that answers with the warning twice, a minute apart, is taken for a page that doesn't exist
  and is skipped (logged as `mo_revisor.section_page_refused`; a re-run tries it again). Three skipped in a row
  stop the load, since that is a real warning, and so does a total above max(20, 0.5% of the pages) however
  they are spread; the run ends with `mo_revisor.sections_skipped total=N`.
- Several versions of one section can be in force side by side: a later version with a future effective date
  (27.117 has one effective 28 Aug 2026 and one effective 1 Jul 2027), or conflicting enactments of the same
  year (`MultiEnact.aspx`). `fct_statute_sections.is_current` marks the in-force version with the latest
  effective date.
- Section numbers aren't always `NNN.NNN`: there are four-digit sections (`1.1001`), letter chapters (`30A`),
  and the uniform codes number sections article-section (`400.3-505`, `456.4A-411`).
- Text: paragraphs are `p.norm` blocks. Tables (fee schedules, forms) come wrapped in `div`s and are kept one
  row per line, cells tab-separated. Soft-hyphen spacer paragraphs around tables are dropped.
- History notes have several act forms: `L.` (enacted), `A.L.` (amended), `A.` (amended, in the 1949 revision's
  notes), and `Repealed L.` in repeal notes. Older acts are cited by session-law page (`p. 1428`) and name no
  bill. Bills are joined by `merged with` (several bills changed the section in one session) and `&` (combined
  bills: `S.B. 299 & 40` is one substitute carrying SB 299 and SB 40; only the first, the lead bill, passed, so
  `fct_bill_statute_links.is_lead_bill` is false for the rest and `combined_into` names the lead; the House
  list shows the others as failed). A bill after `&` may repeat its head (`H.B. 237 & H.B. 238`, or another
  type: `H.B. 5 & S.B. 7`); a bare number takes the type before it. `and` (`H.B. 1270 and H.B. 2032`) is ambiguous:
  it joins the bills of one combined act (2004 `S.B. 968 and S.B. 969` is one act led by SB 968) and also separate
  acts (2018 `H.B. 1606 and S.B. 743`, where SB 743 is also cited alone). A bill after `and` is a lead bill only
  when the same year and session cite it as the first bill of an act elsewhere in the notes; otherwise it is
  combined into the lead of its group like one after `&`. The old notes also list a second bill after a comma
  (`A.L. 1978 H.B. 971, S.B. 628`): that piece continues the act before it. `, et al.` belongs to the act before
  it. `S.B` sometimes lacks its last dot.
- Extraordinary sessions: the Revisor writes "1st Ex. Sess." and counts only extraordinary sessions that passed
  bills. The House numbers every special session, so 2018's legislature-called impeachment session (House 183,
  resolutions only) makes the Revisor's 2018 "1st Ex. Sess." House session 184. The Revisor also
  prints "2d", "3d", "4th", "1st.", "First", "Ex. Sess" (no final period), "Extraordinary Session" (1997, no
  number: read as the year's only numbered session, the 2d) and, once, "lst"; all are read. The model maps
  the Nth extraordinary session to the House session named "Nth Extraordinary Session" (`stg_mo_house__sessions`),
  and assumes N + 2 for years that list lacks.
- A repeal or a new version that waits on a contingency is dated 1 Jan 2099 (repeals by 2026 SB 1233; section
  44.098). Staging keeps it as `is_contingent` with no date; the mart's status is `contingent`.
- A version a court held unconstitutional is marked "(all or part is unconstitutional)" in its effective line,
  and the Revisor then also prints the version before it (56.067 and 56.816, both 2014 amendments).
  `fct_statute_sections.held_unconstitutional` carries the mark. `is_current` still picks the newest version,
  because "all or part" doesn't say which text applies.
- `rx.aspx` also lists repealed constitution sections (`V Section 25`); staging leaves them out (the
  constitution is #224). One of them prints the year as "L. 1076" (for 1976).
- Transfer notes read "(Transferred 2013; now 29.351)" or "(Transferred 1978 to 565.004; repealed 1983)".
- Some versions are on both pages: 324.406/60569 and 324.424/60572 are listed contingent on their chapter page
  and printed on `rx.aspx` as "Repealed L. 2026 S.B. 1233" with the 2099 date. `fct_statute_sections` keeps the
  listed row and sets `repeal_pending`.
- One bill can be both `repealed` and `amended` for the same section in `int_mo_revisor__session_law_bills` and
  `fct_bill_statute_links`. A repeal-and-enact-in-lieu act is cited twice in the note ("A.L. 2026 S.B. 888 and
  Repealed L. 2026 H.B. 2637 & 3155", 566.211), once as the repeal and once as the new text. Anyone counting
  "sections a bill repealed" should expect rows for sections it also amended, and filter on `change`. In a repeal
  note "Repealed" covers every "and L." act after it, however long the chain, and any bill-only pieces that follow.
- Some chapters list no sections at all: every section in them was repealed or transferred.
- History notes only cover bills that became law. A pending bill's statute targets are in its text, which
  isn't loaded yet (#175).

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
- The 24-hour notices repeat here too (#156): 74 direct-export rows ($0.51M, report years 2023-26) are notice lines
  that a full report itemizes again; `int_mec__contributions_direct` drops them (see tap_mec Quirks for the rule). The second tier (#542) drops 4 more ($19.6k) whose donor name was misspelled in the notice or the report.
- MEC answers in under a second (the lobbyist search takes about 13 s). The fixed `MOGOV_MEC_PAUSE`
  (3 s) between requests is most of the runtime. A cold run is about 4 requests per export year and
  3 per election date.
- Committee donors on CD1_A carry only a name (`committee`); `mecid` is the receiving committee. To go one hop back
  (who funds the PAC that funds an official, #9), `int_mec__donor_committees` matches that name to the names
  committees file under, in tiers: a curated alias (the `committee_donor_aliases` seed, e.g. HRCC, AMECPAC, MHA PAC,
  each group checked against the committee's filings or its own filed name, carrying its evidence; high confidence), a MECID typed into the
  name, the same name (case ignored; punctuation and other non-alphanumeric characters turned into spaces; runs of spaces collapsed but not removed: "Health PAC" and "HealthPAC" differ, #108), a normalized name (MO = Missouri, Assn = Association,
  ...), and a core name without words like PAC, Political, Action, Committee, Fund, Account (also tried on the name
  outside parentheses, and on a filer's parenthesized short name). A match counts only if that committee was active
  within a year of the gift, and only when it is unique. Measured October 2026 over both feeds ($417M from
  committees): 71% of the dollars match one committee, 1.5% are ambiguous, 27% match nothing, and 0.6% name a
  committee that was not active that year. An exact name match alone gets about 53%. Most of the misses are federal and out-of-state PACs (DRIVE, AFSCME, DGA), which don't file
  with MEC, plus acronyms that no name rule can expand (the common ones, HRCC, AMECPAC and MHA PAC, are in the alias
  seed). Distinct committees can differ only by "MO" vs "Missouri" ("MO Values PAC" and "Missouri Values PAC"), so
  the exact-name tier is tried first.
- Signing off donor aliases. Each row of the `committee_donor_aliases` seed (`dbt/seeds/committee_donor_aliases.csv`)
  carries `checked_by` (who verified the alias against the committee's filings, a name or GitHub handle) and
  `checked_on` (the date of that check, `YYYY-MM-DD`). Both are empty until a maintainer signs the row off; a row
  with only one of them filled still counts as unsigned. To sign one off, read its `evidence` column, confirm it
  against the committee's filings, fill both columns in the CSV, and run `mogov build`. The warn-level test
  `assert_committee_donor_aliases_signed_off` lists each committee with unsigned aliases (`committee_name`,
  `n_unsigned_aliases`, `unsigned_aliases`) and goes quiet once every row is signed. Unsigned aliases still match.
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
- `mo_contribs_clean.csv` loads 97,565 transaction ids twice. The copies differ only in a doubled
  `address_clean`, and about $179M was double-counted. Staging keeps one row per `record_id` (#82).
- The two export layouts overlap for 2020: 19,231 ids appear as both `txn` and `cd1_a_id`. They are the
  same record (committee, date, amount, names and address all match), so staging uses an unprefixed
  `record_id = coalesce(txn, cd1_a_id)` and the newer layout wins (#83).
- The same gift can also appear once in each layout under different ids, by two mechanisms: an amended
  report re-filed in the 2020-2022 export (older report X vs newer "AMENDED X": 267 rows, $0.79M), and a 24-hour
  notice re-itemized in the next full report (28 rows, $4.19M, ~81% of the dollars), plus ~100 rows
  ($0.2M) pairing other reports (8-day-before vs 30-day-after / January Quarterly); e.g. txn 1513443 /
  cd1_a_id 1623513, $100 from Aaron Hankel. Staging drops the older-layout
  row when the newer layout has a row with the same committee, date, amount and donor (first + last name, else
  company / committee / ctrb_name; upper-cased, trimmed), matched one-to-one: the nth older row is dropped only
  if the newer layout has an nth row for that key, so identical same-day gifts inside one layout both stay (#99).
  This removes 397 rows ($5.19M): 290 person gifts ($0.60M) and 107 organization gifts ($4.59M, e.g. the
  Democratic Governors Association's $3.55M of 2020-10-26 gifts, $1.775M into each of C201190 and C201352). 395 of the 397 keys are 1:1; 2 keys have two
  older rows against one newer row and keep the extra older row. Gifts that differ in amount, date, committee or
  name are not matched, so some re-filed gifts may remain.
  Net effect of the dedupe: staging goes from 1,603,397 to 1,486,204 rows ($1.2487B to $1.0550B).
- A "24 Hour" notice is also listed again, as a line of its own, in the committee's next full report, within the same
  layout (#156). The notice (report `24 Hour Expenditure Report-...`, a gift of $5,000+) and the full report's line
  carry the same committee, date, amount and donor. Staging keeps both; `int_tap_mec__contributions` (what committee
  receipts, donor summaries and the campaign-finance fact read) drops the notice line when the same committee's full
  report itemizes the same gift (donor compared by `name_key`: case, punctuation and spaces ignored), matched one-to-one,
  so a notice with no later full-report line and two equal gifts that both appear in full reports stay. Measured
  October 2026: 127 TAP rows, $1.30M. A second tier (#542) catches the same donor spelled differently: among the lines
  left over, a committee/date/amount with exactly one notice and one full-report line, both naming the same city and
  state, is one gift when the names are equal after dropping MO/Missouri, "and"/"of"/"the", legal forms and middle
  initials ("MO Soybean Association" / "Missouri Soybean Association", "James Nutter" / "James B Nutter"), or are a
  typo apart (up to 2 letters, names of 10+ characters, same digits: "Lathrop GPM" / "Lanthrop GPM"; "LIUNA Local 110"
  is not "LIUNA Local 100"). Measured October 2026: 7 TAP rows ($35.4k). A third rule (#557) in the same tier
  also pairs an abbreviation or an added word: word by word one name is a prefix of the other ("deVries & Associates" /
  "DeVries and Assoc", "...Technical Ed" / "...Technical Education") and the longer name has at most two more words
  ("Committee to Elect Jamie Burger HD"); the first word must be equal and the digits match. With several lines in the
  group a notice is dropped only when it has exactly one name-compatible full-report line, that line has exactly one
  name-compatible notice, and no line in the group lacks a donor name. Measured October 2026: 4 more TAP notices
  ($10.9k). Left in place on purpose: two compatible candidates on either side, names that need outside knowledge
  ("UP Railroad Company" / "Union Pacific Railroad Company"), and different donors who happened to give the same amount.
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

Quirks:
- The members file also lists the Presidents, with chamber `President` and ICPSR ids 99912/99913 (two rows each
  in the loaded congresses). `stg_voteview__members` keeps only House and Senate rows.
- The votes file carries the President's announced position on some roll calls as vote rows under those same
  999xx ICPSR ids, with the roll call's chamber (House or Senate; 941 rows in the loaded congresses). They aren't
  members of a chamber, so `stg_voteview__votes` drops icpsr >= 99000 explicitly. A test on that column fails if
  the filter goes.
- The rollcalls file has only House and Senate rows, and the source `accepted_values` tests on all three files
  flag any new chamber value; staging drops unknown chambers either way.

## house_fd: U.S. House financial disclosures

Flow: [diagrams/sources/house_fd.svg](diagrams/sources/house_fd.svg)

Yearly national index plus each Missouri filing's PDF, split into text lines.

- Lands: `house_fd_index`, `house_fd_pdf_lines`.
- Shard units: index years and PDF URLs.

Quirks:
- Scanned paper filings (DocID 8xxxxxxx/9xxxxxxx) have no text layer. They land as one
  `has_text = false` row, so the gap is visible.
- Periodic transaction reports live under `ptr-pdfs/`; everything else is under `financial-pdfs/`.
- Index type `H` is the New Filer Report (PDF header `Filing Type: New Filer Report`), filed by new members; a
  separate report from that year's Annual Report (O). The loader reads it like O/A/P/C/T. Other index types
  (D, X, G, E, B, W) are not downloaded.

## senate_efd: U.S. Senate eFD (opt-in)

Flow: [diagrams/sources/senate_efd.svg](diagrams/sources/senate_efd.svg)

- Lands: `senate_efd_filings`, `senate_efd_rows`.
- Enable with `MOGOV_ACCEPT_SENATE_EFD_TERMS=1`, which accepts the use statement (5 U.S.C. § 13107(c),
  formerly 5 U.S.C. app. § 105(c)) on your behalf.

Quirks:
- Requests are CSRF-protected, so the loader accepts the use statement and then searches.
- Paper filings are page images: they're recorded with `is_paper = true` and not parsed.
- Report pages aren't cached.
- Since 2026-10-24 Akamai Bot Manager answers the agreement `POST /search/home/` with HTTP 403 ("Access
  Denied"), because a plain HTTP client can't pass its browser check. The loader now fails right there with a
  clear error instead of on the next call. It is blocked until the maintainer decides how to proceed
  (see #161). Meanwhile `mogov run --allow-failed-loader senate_efd` builds on the last landed data.

### Alternatives to the eFD scrape (research for #185, checked 2026-10-25)

No free or openly licensed alternative is both current and covers annual reports (LegiStorm, a paid
subscription, may; its format and terms are unverified). Recommendation: keep the manual import (#190) as the
working path and ask the Senate Office of Public Records for a sanctioned feed (#277).

| Candidate | Covers | Freshness | Access | Terms | Fit |
|---|---|---|---|---|---|
| Senate Office of Public Records (OPR) | everything in eFD | live | no bulk/API/allowlist is published; contact OPRGeneral@sec.senate.gov, (202) 224-0322 | 5 U.S.C. § 13107(c) use limits apply (no unlawful purpose, commercial purpose other than news/communications media, credit rating, or soliciting money) | the only official route; maintainer must ask |
| `jeremiak/us-senate-financial-disclosure-data` (GitHub) | only `output/transactions.csv`: transaction rows from PTRs and from annual reports' transaction section (no assets, income, liabilities, positions, gifts or travel); 1,824 report ids, 2012 to 2020 filings | last push 2024-01-15; the CSV's newest filing is 2020-06; `reports.json` is broken (3,381 entries, 31 unique) | git clone, no key | CC-BY-SA-4.0 (share-alike), underlying data still subject to § 13107(c) | `report-id` is the eFD UUID, so ids map after lowercasing; stale, useful only as a 2012-2020 cross-check of transactions |
| `timothycarambat/senate-stock-watcher-data` (GitHub) | PTRs only | last push 2021-03-16; no licence | git clone | none stated | stale, PTRs only |
| Disclosed Capitol | PTRs (annual reports unclear) | claims minutes | API key, credits, rate limits | bulk resale barred; personal/news use only without written permission | paid, restrictive; do not build on it |
| [Financial Modeling Prep](https://site.financialmodelingprep.com/developer/docs) `senate-latest` | PTR trades | not verified | API key, paid tiers | commercial vendor terms, not read | PTRs only; not evaluated further |
| [Quiver Quantitative](https://pypi.org/project/quiverquant/) | congressional trades | not verified | API key, $30/month per the quiverquant PyPI README v0.2.6 (2026-05-07) | terms page not retrievable | PTR trades only |
| [LegiStorm](https://www.legistorm.com) | Senate PFDs indexed by member, reportedly incl. annual, amendments, termination, new-hire and PTRs; a 2026 Annual report appears on Grassley's page | current | paid subscription | not read | format and terms unverified; possible but needs a subscription decision (see needs-user issue) |
| Capitol Trades | trades | not verified | no public API; scraping only | terms not retrievable | not usable |
| OpenSecrets personal finances | members' assets and liabilities | bulk CSV last seen for 2004-2007 (2009 notice) | site closed to our fetch; current terms unverified | CC BY-NC-SA in 2009; commercial use by fee | not verified current |

Notes: every third-party feed re-publishes eFD data, so the § 13107(c) use limits likely apply to it (a legal
question for the maintainer / OPR). The only candidate with a stable id that maps to our `url` column is jeremiak's
`report-id`. Third-party feeds carry PTR trades but not annual-report sections (assets, income, liabilities,
positions, gifts, travel) that `stg_senate_efd__items` needs.

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
- Amended filings sit beside originals in `fct_disclosures`: Senate "annual report for cy 2022 (amendment 1/2)",
  House "amended report", and two AO-10 pdfs for one judge-year (`..._1.pdf`). `is_latest_version` marks the
  newest version per filer, source, report year and report (annual report plus its amendments). Count or sum
  items only over `is_latest_version`; the filing list shows all. It assumes an amendment restates the whole
  report, and a House amendment that is a scan with no extractable text never supersedes a readable report.
  Periodic transaction reports, candidate reports and extension requests are separate filings, never collapsed.
  The index has no amendment number either, so a House amendment's `report_version` is its position by filing date
  among the amendments of its report (ties: numeric doc id).
  The Clerk index does not say which report a House amendment amends, so it is taken to amend the latest annual,
  candidate or termination report the filer filed that year on or before it (an amendment of a candidate or
  termination report supersedes that report only) (#142, #463). Index type H is a New Filer Report (the PDF header says
  "Filing Type: New Filer Report"; e.g. Carey OH15 #10050139, Alford MO04 #10051960), a separate report from the
  Annual Report (O) of the same year, so it is a base like a candidate report: an amendment filed after an H amends
  it and supersedes it, while an H and an O of one year are both kept latest (Carey OH15 2022, Wied WI08 2025; for
  O, A, H, A as in Miller WV03 2018 the first A supersedes the O and the second the H). Whether both should be
  latest, and which report a later amendment amends, is open (#572). Of 346 H filings only 3 have an O for the same
  filer and year, 233 have an extension request X that year, and the H counts follow the freshman classes of
  election years (Missouri freshmen Alford and Burlison (2022), Onder and Bell (2024) each have an X then an H in
  August and no O). Periodic transaction reports and the remaining "other" kinds (W withdrawal, B, E, G) are never a base.
  The "Period Covered: mm/dd/yyyy-mm/dd/yyyy" line in the amendment's PDF text (`int_house_fd__period_covered`;
  candidate reports and their amendments carry it, annual and termination reports do not) refines this: the base
  covering through the same last day wins, and an amendment with such a line is taken for an amendment of an
  annual report only as a last resort, when no candidate or termination report is on file.
  Measured on the Clerk index (all filers, 2,095 amendments; name-matched, ignoring the Period Covered line, which
  is loaded for Missouri filers only, so approximate): counting H as a base re-points 195 amendments (169 off a
  candidate or termination report, 1 off an annual report, 25 that had no base), W, B, E and G re-point none; before
  H was added, counting termination reports as bases re-pointed 18. For Missouri officials neither change moves a
  row: the rebuilt `fct_disclosures` is identical to origin/main (EXCEPT ALL both ways, 0 rows differ). Only 3 of
  the 10 Missouri amendments carry the line.

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
- Time to disposition (`fct_judge_time_to_disposition`): only the federal districts (`moed`, `mowd`) have a
  judge (`assigned_to_id`) and filing and termination dates on a docket; the state courts (`mo`, `moctapp`)
  have none, and `ca8` has no judge. Of 173,882 district dockets with a judge, 165,797 have both dates; 93
  of those end before they were filed (a source error) and are left out of the median.
  The median is per case type, civil and criminal apart: criminal medians run about twice civil ones
  (Stephen R. Clark: civil 165 days, criminal 462) and the mix differs by judge. Case type is the docket-number
  type (`4:25-cr-00236` is `cr`), taken from `federal_dn_case_type` where CourtListener parsed it (about 16% of
  these dockets) and from the number itself otherwise. Of the 173,882 dockets: civil 164,058 (`cv` 164,027,
  `md` multidistrict 31), criminal 3,776 (`cr`), miscellaneous 5,967 (`mc` 5,082, `mj` 646, `sw` 194, `wi` 30,
  `sm` 13, `pr` 2: warrants, subpoenas, complaints, not cases; left out) and 81 other (`fp` 76, `cn` 2, `sc` 2
  and one with a date in the docket-number field; left out, pending #465). Only 2,152 of the 3,776 criminal
  dockets have both dates (2,149 are measured: 3 end before they were filed), so criminal coverage is thin. One docket (`1:00-cr-00008`) has a `cr` number but is
  a civil suit; CourtListener's own type (`cv`) wins.
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
- Besides biographies and the judges, dbt reads the executive chapter's "Historical Listing" tables (every governor,
  lieutenant governor, secretary of state, auditor, treasurer and attorney general since 1820, terms in whole years)
  into `int_bluebook__statewide_officeholders`.

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
  when exactly one member fits. The payroll prints suffixes inside the surname ("BRATTIN JR.", "HADEN DVM"),
  legal compound surnames ("WALSH MOORE, BRIDGET" is Bridget Moore, "SCOBEE POUCHE, SEAN" is Sean Pouche),
  and "VANSCHOIACK" for the House roster's "Van Schoiack"; all are compared without those differences.
  Members who share a surname are paired by first name (Ed = EDWIN, Patty = PATRICIA); one member and one payee
  left over once the others are paired also pair, at `medium` (Mike Jones = "JONES, MICHAEL J"). A payee also pairs, at `medium`, with the member whose usual
  name is the payee's middle initial when nobody else fits that way: "SMITH, DAVID C" is David Cody Smith, known as
  Cody Smith (R, HD163), and "SMITH, DAVID T" is David (Tyson) Smith (D, HD45 then HD46, from 2021). Others are
  matched by name. Open States gives some seats no start date (stored as 1900-01-01), so a seat counts from the
  member's first roster year in that chamber (House or Senate, each on its own) instead, and a by-name match of
  legislator pay is held to the years the member sat, unless nobody else holds the surname that year (a final check
  after a term, or earlier service Open States records as another person: Steve Roberts' 2017-20 House pay stays his
  because the "Steven" and "Steve" Roberts records are now one person, #263). A payee whose first name fits a member
  whose seat ended the December before, or that January (Open States ends the 2022 and 2024 departures in January),
  and who earned under half the year's top pay, is that member's final check (unless the member held a later seat in
  the chamber), and neither it nor the member competes for the seats held now ("BLACK, LINDA R." 2017 beside Rusty
  Black's "BLACK, JAMES R"). In October 2026, 2025 pay matched all 155 representatives and all 33 senators.
- The current year's dataset appears in January of the following year.
- Federal officials (Congress, federal judges) are paid by the U.S. and are not in this source.

## mo_sos_elections: Missouri Secretary of State official election returns

Flow: [diagrams/sources/mo_sos_elections.svg](diagrams/sources/mo_sos_elections.svg)

The Secretary of State's certified returns (https://www.sos.mo.gov/elections/results): one statewide "Grand
Totals" PDF per general and primary election, as announced by the Board of State Canvassers. Each race lists
its candidates with party, votes and percentage of votes, and "n of n Precincts Reported". Judicial retention
(Supreme Court, Court of Appeals, and circuit judges under the nonpartisan plan) is a Yes Votes / No Votes pair per judge.
Two marts come from it: `fct_election_races` (winner, runner-up, margin, uncontested flag, write-in share;
serves the uncontested-wins award in #28) and `fct_judicial_retention` (Yes and No votes, Yes %).

- Lands: `mo_sos_election_rows`, one row per printed PDF line: the PDF url, page and line, the verbatim text, a
  structural `kind` (contest `header`, `candidate`, `total`, `party_total`, `other`), the contest's sequence number in
  the PDF and, for candidate rows, the cells (name, party, votes, % as printed). Nothing is cleaned in Python; parsing
  numbers, write-in flags and contest types is dbt (`stg_mo_sos_elections__*`).
- Coverage: the 14 general and primary elections from August 2012 to November 2024 (7 generals, 7 primaries; about
  17,700 lines). The election list is read from the results page on every run, so each new canvassed election is picked
  up by re-running the loader. Not loaded: presidential preference primaries (a different layout with no party
  column, party codes and "Last, First" names; the March 2020 PDF has no text layer at all), the single-district
  special-election PDFs, the "Results by County" PDFs, the 1996-2011 results (a separate page, not verified), the
  precinct files (sold by the Elections Division) and Election Night Reporting (`enr.sos.mo.gov`, JavaScript with no
  downloads). The August 2026 primary is on Election Night Reporting only until its PDF is posted.
- Terms: none stated on the site. The loader sends the project User-Agent, fetches one PDF at a time with a
  2 second delay, and caches PDFs for good once an election is four months old (the newest is re-checked daily).
- Shard units: elections (one PDF each); the PDFs are small (about 1 MB), so a full run takes about 90 seconds.

Quirks:
- Column positions, not text, separate the name from the party: the loader clusters words into lines and splits a
  candidate row at the party column (left of the header's "Party" word minus 30 points). Names with commas or
  suffixes ("Emanuel Cleaver, II", "John A. Hartwig, Jr.") stay whole.
- A president/vice-president ticket wraps onto the next line in some years, so the running mate's last name can be
  missing or on a separate `other` line ("Hillary Rodham Clinton, Timothy", then "Michael Kaine").
- In a primary a contest lists every party's candidates with "Party Total" lines; percentages are within the party.
  Each party's ballot is one race in `fct_election_races` (`race_party`), and "Total Votes" spans all parties.
- A Court of Appeals header can list several judges (2014-2022), each a Yes row followed by a No row. `subcontest_seq`
  counts the Yes rows. In 2022 the PDF prints a single "Total Votes" for four judges (the first judge's), so the
  reconciliation test only compares contests with a total per judge.
- Typos and layout losses in the PDFs, kept as printed: 2016 "No Votes 252,827 59.5" (the "%" lost; parsed), 2016
  "No Votes 40.9%" (the vote count lost; the judge keeps the Yes figures and `no_votes` is null), and 2018 State
  Representative District 66 prints its total on two lines ("10,376" and "Total Votes"). The 2014-2020 ballot
  measures use an older layout ("Constitutional Amendment 1 Ballot Issue Yes: 499,581 Yes: 50.1%", then "No: 497,091
  No: 49.9%"). The loader lands those lines unsplit (`kind = other`); `stg_mo_sos_elections__lines` recognises them and
  gives them the same cells as the other years (#331).
- 2014 primary Constitutional Amendment 1 (right to farm): the printed Yes 499,581 / No 497,091 lines are pre-recount
  and uncertified. The certified recount gave Yes 499,963 / No 497,588, and the printed Total Votes 997,551 is the
  recount total. A ballot-measure mart must not treat the staged Yes/No rows as certified for this measure. Amendment 9
  on the same page (729,750 + 246,515 = 976,265, printed 976,267) is a 2-vote inconsistency in the PDF itself.
- Candidate-less ballots: a Yes/No pair named like the contest title is a ballot measure (staged as
  `contest_kind = 'ballot_issue'`, not in a mart); otherwise it is retention.
- Uncontested means exactly one candidate on the ballot, write-ins not counted (a write-in with 19 votes does not
  make the race contested). `write_in_share` carries the write-in votes for the 5% rule. In a primary it is per party
  ballot. Races whose only entries are write-ins are dropped. Winner is the top vote getter; the PDFs do not print the
  number of seats, so a vote-for-two race would show its second seat as the runner-up.
- Margin is winner minus runner-up (write-ins excluded) in votes and in points of the race's total votes
  (`margin_pct`), null when uncontested. Retention is `is_retained` when Yes votes exceed No votes (the printed Yes share above 50 where the No line is lost).
- Links to officials: `winner_official_id` / `judge_official_id` are set only when the winner is a current official
  with the same name in the same office and district (suffixes ignored, Supreme Court and Court of Appeals judges by
  name); losers, former officials and circuit judges are unlinked. Officials who moved districts after redistricting
  therefore do not link for older elections.
- Checks: contest vote sums equal the PDF's printed totals where a total exists (3,481 of 3,486 contests and judges),
  printed percentages sum to 100 within rounding, and figures copied from the 2024 general PDF (Governor, U.S.
  Senator, State Representative districts 33 and 34, Broniec 63.1% and Gooch 62.2%) are asserted exactly.
- Special elections on primary day: the 2014-08-05 primary PDF also holds three special elections for unexpired terms
  (State Representative districts 67, 120 and 151, titled "..., unexpired"). They print no "Party Total" lines and
  their percentages sum to 100 across the whole contest, so they are one race across parties (`race_party` is null),
  not one uncontested race per party. A primary contest is split by party only when it prints Party Total lines
  (`stg_mo_sos_elections__contests.has_party_totals`).
- The 2020 general PDF's header reads "Unofficial Election Returns" even though it is the Secretary of State's
  Grand Totals file for that election; the loader does not rely on the header.
- A candidate or contest name that wraps onto a second PDF line can be cut off at the first line (the second line
  is not rejoined). Examples: 2018 primary "William Christopher (Chris) McDonough", 2018 general "Martin Luther
  Dzerzhinsky Lindstedt", and the 2020 header "Associate Circuit Judge - Circuit 22 - Div 24 & 29".

## mo_state_expenditures: Missouri state expenditures

Flow: [diagrams/sources/mo_state_expenditures.svg](diagrams/sources/mo_state_expenditures.svg)

data.mo.gov's "<fiscal year> State Expenditures" datasets (the Missouri Accountability Portal's spending data):
for each fiscal year (July to June), the total each state agency paid each payee per category and detail line.
Under the agency `LEGISLATURE` it lists every legislator's per diem (`LEGISLATIVE DAILY EXPENSE ALLOWANCE`) and
`IN-STATE MILEAGE`; every other agency's rows are payments to vendors and people. `fct_legislator_expenses`
pairs the legislators with officials.

- Lands: `mo_state_expenditures`, one JSON row per dataset row exactly as the API serves it (`fiscal_year`,
  `agency_name`, `category_description`, `detail_description`, `vendor_name`, `payments_total`, all text), keyed
  `<fiscal year>:<n>` in `:id` order. All agencies land, about 100,000 to 130,000 rows a year, so the vendor
  payments are on hand for later use. Optional like the other stage-1 JSON tables: `mogov build` creates an
  empty placeholder when it has not been loaded.
- Window: `MOGOV_LOOKBACK_YEARS`, counted as fiscal-year numbers (2017 to 2026 by default: about 1.1M rows).
  Shard units: fiscal years (one dataset each; ids from the Socrata catalog). Pages of 50,000 rows with a
  half-second pause; a page that comes back short fails the run rather than landing a partial year.
- Terms: no licence field on the datasets. The state's data policy (https://mo.gov/data-policy) says the user
  accepts the data as is, at their own risk, and that "applications using data supplied by this site must
  include" its disclaimer: "The data made available here has been modified for use from its original source,
  which is the State of Missouri. THE STATE OF MISSOURI MAKES NO REPRESENTATIONS OR WARRANTY AS TO THE
  COMPLETENESS, ACCURACY, TIMELINESS, OR CONTENT OF ANY DATA MADE AVAILABLE THROUGH THIS SITE..." (full text on
  that page). The site that shows this data, and the State Employee Pay data above, must carry that notice;
  the frontend footer (`Layout.astro`) carries it on every page.

Quirks:
- A row is one payee's annual total for one agency and detail line, not one payment. FY2023 `LEGISLATURE` has
  240 per diem rows ($1,799,338.96) and 295 in-state mileage rows ($880,139.52), one per payee.
- Negative totals are refunds and corrections and are kept (the smallest is -$18,418). No legislator per diem or
  mileage row has been negative. The largest total is $11.24B (the Medicaid recipient line, FY2026), so the
  sanity test allows $20B.
- Payees are people and vendors in one column (`vendor_name`), mixed with lines such as "PROCUREMENT CARD
  PAYMENT". Legislators appear under their full legal name, "ATCHISON, FRANKLIN DARRELL", where the payroll
  prints "ATCHISON, FRANKLIN D". Payees therefore pair with officials through the payroll names already matched
  in `fct_salaries` (same legal-name form), not through the officials' own names: surname without suffixes plus
  a fitting first name, middle initials that agree when both sides carry one ("SMITH, DAVID T" is not "SMITH,
  DAVID C"), and a payroll row in the fiscal year's calendar years (fiscal year 2023 is July 2022 to June 2023,
  so 2022 or 2023 payroll). One best-fitting official and one payee per official, line and year are required;
  otherwise the payee is left out. `high` means equal first names and either a shared middle initial or a
  surname no other legislator on the payroll holds that year; nicknames ("DAVE" for David) and shared surnames
  without a middle initial are `medium`.
- Because the payroll rows come from `fct_salaries`, which covers current officials, former legislators' per
  diem is not linked. In October 2026, fiscal year 2026 paired 176 of 193 per diem payees (162 high), fiscal year
  2025 paired 177 of 241, and the share falls to 19 of 229 for fiscal year 2017. Unpaired payees are former members.
- The portal serves an occasional sparse row with only some columns set (FY2025 has `fiscal_year: "KEVIN KRAUS"`
  and `agency_name: "11408"`). It lands as published and staging drops it.
- Datasets are replaced when the state republishes them (FY2023 `rowsUpdatedAt` 2024-09-26), so a run replaces
  the whole fiscal year. The fiscal year numbered 2026 ended in June 2026; the next appears after it closes.
- Per diem is claimed per day attended and mileage follows distance, so neither is a measure of performance.

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

- Lands: `epa_frs_facilities`, `epa_frs_organizations`, `epa_frs_naics`, `epa_frs_sic`, `epa_frs_alt_names`, one row per CSV row of
  `MO_FACILITY_FILE.CSV`, `MO_ORGANIZATION_FILE.CSV`, `MO_NAICS_FILE.CSV`, `MO_SIC_FILE.CSV` and `MO_ALTERNATIVE_NAME_FILE.CSV` from the Missouri state file
  (`https://ordsext.epa.gov/FLA/www3/state_files/state_combined_mo.zip`, about 35 MB). The payload is the row
  as a JSON object keyed by the CSV header.
- Shard units: the five CSV files. The zip is downloaded once and shared.
- U+FFFD in EPA's own file: the state zip already contains the replacement character (bytes EF BF BD) in a few
  names and addresses (4 in `MO_FACILITY_FILE.CSV`, 2 in `MO_ORGANIZATION_FILE.CSV`, 8 in the alternative-name file),
  where EPA lost a non-ASCII letter. The loader decodes strictly, so it adds none; raw stays as EPA sent it.
  EPA's other records spell the same words without an accent ("DECOR PLUS", "MARBLE DECOR INC" in its program and
  alternative-name files), so nothing attests "DÉCOR". Staging repairs a name that has U+FFFD in this order: a row of the
  `epa_frs_name_corrections` seed (a maintainer override; each row cites the EPA record that attests it), else the
  alternative name from `stg_epa_frs__alt_names` (`MO_ALTERNATIVE_NAME_FILE`, one row per program record) with the same
  registry id (organizations: the same registry id, program system and program id) that equals the damaged name with
  each run of U+FFFD standing for exactly one character (`mogov.damaged_name_pattern`; "D�COR PLUS" matches
  "DECOR PLUS", "MARBLE D��COR INC" matches "MARBLE DECOR INC", "DECORATING PLUS" does not), when exactly one distinct
  alternative name fits; with none or two different fits, the U+FFFD is dropped. The generic rule covers all three
  damaged names seen so far (the facilities DECOR PLUS and MARBLE DECOR INC, and the DECOR PLUS owner and operator
  rows). The seed still holds those three known cases, so a raw directory without alternative names builds with the
  same names; once alternative names are loaded its rows are redundant and can be retired, and it stays for a future
  name the alternatives cannot repair. The 2026-10 address
  with U+FFFD ("17123 HWY 60�") has no alternative and just loses the character. `assert_replacement_char_fixed`
  fails if one survives; `assert_epa_frs_name_correction_keys_exist` fails if a seed row matches no staged row. A raw
  directory landed before `epa_frs_alt_names` existed gets an empty placeholder from `mogov build`; the seed covers the
  known cases until `mogov load epa_frs` is re-run (a new damaged name would then lose its letter).
  `stg_epa_frs__alt_names` mirrors raw, so alternative names containing U+FFFD stay there; the repairs never use them.
- Stray commas and tabs: EPA writes many names, addresses and cities with a trailing comma ("BUTTERBALL,",
  "900 WATSON DR,") or trailing tabs, and some owner names too. Staging (`mogov.clean_registry_text`) collapses
  whitespace runs and cuts leading/trailing commas, semicolons and whitespace from facility name, address, city and
  organization name; "INC." and single inner commas stay. Names that were only separators or empty become null (60
  sites; the sites tables say "unnamed site"). A doubled inner comma becomes one
  ("LIPPERT FAMILY FARM,, LLC" shows as "LIPPERT FAMILY FARM, LLC") (#381).
  A single space before a comma goes too ("NEMO FEEDS , LLC" shows as "NEMO FEEDS, LLC", "T 33N ,R 04W" as "T 33N,R 04W") (#399);
  a run of space-comma pairs collapses to one comma ("A , , B" shows as "A, B"). "K-BAR-L ;;C" (facility 110013336416) is
  left as is: it is likely a shifted-hand typo for "K-BAR-L LLC", not a separator, so it is not rewritten.
- HTML entities: a few names and addresses carry entities ("D&AMP;A BARRACKS", "HOLCIM &#40;US&#41; INC",
  "LEE&#39;S SUMMIT"; 8 facilities and 1 organization name in the Oct 2026 file). `mogov.clean_registry_text` decodes `&AMP;`,
  `&amp;`, `&#39;`, `&#40;` and `&#41;`; a bare "&" ("AT&T") is untouched. `assert_epa_frs_text_has_no_html_entities`
  fails if another entity shows up (#398).
- `epa_frs_sic` joined the loader after the other three. A raw directory landed before that has no SIC table;
  `mogov build` then creates an empty placeholder (like the other late-added or optional JSON tables in
  `db.OPTIONAL_JSON_TABLES`), so the SIC fallback finds no codes and those sites show no industry until the
  loader is re-run. Bare `dbt build` does not create placeholders: use `mogov build`.
- Districts: point-in-polygon of the facility's coordinates against the current `dim_district` boundaries.
  The geometry functions are dispatched per backend (`macros/compat/spatial.sql`); on DuckDB they need the
  `spatial` extension, which `dbt/profiles.yml` loads (downloaded on first use).
- Donor match, two ways (`matched_by`):
  - `same name`: the donor organization's name equals the facility's, owner's or parent company's after
    lower-casing, turning punctuation into spaces and dropping a leading "the" and legal-form words (Inc, LLC, Co,
    Corp...).
  - `same company`: both names carry one brand from the `company_brands` seed. Corporate money mostly comes
    from PACs named after the brand ("Ameren Missouri PAC", "Spire PAC", "AT&T Missouri Employee PAC"), while
    sites are filed under legal or subsidiary names ("UNION ELECTRIC CO", "LACLEDE GAS", "SOUTHWESTERN BELL
    TELEPHONE", "KANSAS CITY POWER & LIGHT"). The seed covers the largest corporate donors with Missouri sites.
  - In October 2026: 502 (official, facility) pairs by name and 1,541 more by brand, for 122 officials.
- Each matched site also carries the matched donors' first and last contribution year, `match_confidence`
  (`medium` when any of that money was tied to the official by name only) and, in `fct_jurisdiction_business_donors`
  (one row per official, site, donor and filing page; #370), the donors and their links. A page is the MEC committee
  matched to the official, which is not filtered to the donor, or the FEC disbursements of the donor's committee
  filtered to the receiving committee; a donor filed on both keeps both. Line breaks in a donor name become spaces so a
  line never splits; the frontend writes them as `<url> <donor name>` lines, which in the published sites.csv sit in one
  cell. A donor with no page has one row with a null `source_url`.
- Industry: the NAICS code the most program systems (RCRAINFO, NPDES, AIR, ...) give, one count per system however many records it has, taking primary codes first (`naics_source` `naics`,
  31% of the geocoded sites in October 2026), then codes FRS leaves UNKNOWN (`naics_unknown`, 2%), then SECONDARY
  ones (`naics_secondary`, 0.1%). A real NAICS code is more precise than a SIC-derived sector, so only a site with
  no NAICS code at all falls back to its SIC code (1987 Standard Industrial Classification, from
  `MO_SIC_FILE.CSV`; a primary code before an unknown or secondary one), mapped to a NAICS sector through the
  `sic_naics_sectors` seed, a hand-written table from SIC major group (two digits, longer where a group splits
  across sectors) to NAICS sector. That gives a sector, not a NAICS code: `int_epa_frs__facilities.naics_code`
  then holds the two-digit sector prefix and `naics_source` is `sic` (23%). Together they cover 56% of the
  geocoded sites; the rest have neither code. Where a site has both, the non-primary NAICS code and the SIC
  sector agree on the sector for about 90% of sites. Among codes tied on tier and program systems, the tie-break
  runs in order: the code in the SIC sector (NAICS 31-33 count as one sector) wins; then NAICS 238910 and SIC 1629
  (construction stormwater permits) lose to any other code; then the lowest code.
  The SIC sector is ignored for that tie-break when the site's SIC code is itself tied on tier and program systems
  with a SIC code in another sector (the lowest code was picked arbitrarily), and for SIC 1629. This changes the
  NAICS code of 56 facilities against the lowest-code rule.
  About 10,400 of the SIC-filled facilities are SIC 1629 (heavy construction), likely construction stormwater
  permits. Every seed row was checked in October 2026 against the Census 1987 SIC to 2002 NAICS concordance,
  carried to 2022 NAICS through the Census 2002-2007, 2007-2012, 2012-2017 and 2017-2022 concordances, and
  3 or 4 digit rows override the group where a code maps to a single other sector (4922/4923 gas transmission
  48, 6798 REITs 53, 6552 land subdividers 23, 7331/7335/7336 54, 7383 51, 7384 81 and others). Groups still mapped
  to one sector despite straddling (73 business services, 79, 80, 87, 89) take the majority one. Codes that tie
  between two sectors (0752 11/81 kept 81; 4923, 7331, 7335, 7383, 7378; 89) or split in the concordance with no
  clear majority (1389, 2771, 3295, 5099, 5171, 5441, 5699, 5712, 7353) are listed in the seed description. The
  hand table stays rather than a generated one: the concordance has 1,000+ SIC codes mapping to six-digit
  industries and needs a four-file NAICS vintage chain, far more than a sector label needs.
- `rpt_district_business_industries` counts each official's sites by NAICS sector (`naics_sectors` seed, from
  the first two digits of `naics_code`, which for a SIC-derived site is already the sector prefix). The profile
  page ships only the donor sites plus these counts: a U.S. House district holds up to ~10,500 sites, too many
  for the per-official JSON budget.

Quirks:
- A few rows fuse two records onto one line (a closing quote is missing: `...,"O"110015893693",...`). DuckDB's
  CSV reader, even with `ignore_errors`, dropped 35 good organization rows after each such line, so the
  loader reads the files with Python's csv module. The two malformed rows per file land with their values
  under `_fields` and drop out in staging.
- About a third of the sites (36k of 112k in October 2026) have no coordinates and so no district. 54 have
  coordinates outside Missouri.
- About 44% of geocoded sites have neither a NAICS nor a SIC code (see Industry above), so for almost every
  official (198 of 201 in October 2026) the largest per-sector group is "No industry code". FRS programs often
  leave the NAICS code blank, which is why the SIC fallback exists.
- Organization types are mostly `UNKNOWN`, so government sites are also recognized by name ("City of ...",
  "... County", "... School District", "Public Works") as well as by a government org type or federal agency.
- One owner per facility is kept: owner/operator, then owner, operator, permittee, preferring a known org
  type.
- Branded fuel stations carry the brand in their name but are mostly independently owned ("BILL S PHILLIPS
  66"), so oil brands are not in `company_brands`.
- Missouri Accountability Portal (mapyourtaxes.mo.gov, also the "State Expenditures" datasets on data.mo.gov)
  was checked for the same purpose and not used: its files have agency, category, vendor name (cut at 30
  characters) and amount per fiscal year, with no vendor address, and include employees' reimbursements.

## mo_auditor: Missouri State Auditor audit reports

Flow: [diagrams/sources/mo_auditor.svg](diagrams/sources/mo_auditor.svg)

- Site: https://auditor.mo.gov/AuditReport/Reports, backed by the JSON list `/AuditReport/SearchAudits`. No auth. The loader
  keeps to about 1 request a second in total: the throttle is shared by every shard on the machine (`http.host_throttle`).
- Lands: `mo_auditor_reports` (the list rows verbatim plus `search_year`) and `mo_auditor_ratings` (the rating sentence read
  from a PDF, with its url, page and extraction status). First full run: 3,494 reports (1999 to 2026), 1,124 PDFs read (the first run read 1,125 before #439 narrowed the unrated-title pattern),
  about 30 minutes.
- Quirks:
  - An unfiltered list call returns only the newest 1,000 rows, so the loader asks one year at a time and fails loudly if a
    year ever reaches 1,000.
  - The rating is not in the list. It is the sentence "In the areas audited, the overall performance of this entity was
    Good." in the one-page Citizens Summary PDF (`citz_sum_fk`) or, when there is none, in the first pages of the full
    report. pdfplumber sometimes splits a word of that sentence, so the match ignores spaces.
  - Ratings start in 2012. Financial statements (singular or plural), county-wide fire protection district reviews (no rating sentence; a single district's own audit is rated and is read), monthly filing reports, follow-ups, property tax rate filings,
    compilations and the state's annual financial reports (titled "Comprehensive Annual Financial Report" until 2021, "Annual
    Comprehensive Financial Report" since 2022) are never rated and are not downloaded. Performance audits and special reports have no sentence (status
    `no_rating_sentence`). A few 2012-2014 summaries left the template unfilled ("was XXXX"); staging gives them no rating
    (`placeholder_rating`).
  - The link for report 2013-009 (the 2012 Comprehensive Annual Financial Report) is a dead PDF (`Repository/Press/2013-009.pdf`
    404s; the first full run recorded status `http_404`). It is no longer fetched, since annual financial reports are skipped by title.
    The "Report on Internal Control..." companions of the annual financial report have a Citizens Summary, which is still read
    (status `no_rating_sentence`).
  - The ratings cover only the areas audited. A county's rating is the county's, never one official's: only audits of a
    statewide office (seed `mo_auditor_statewide_entities`) are linked to officeholders, in `fct_audit_report_officeholders`
    (#323, policy #333: everyone in office during the years the audit covers). Former holders come from the Official
    Manual's "Historical Listing" tables (`int_bluebook__statewide_officeholders`; whole years only). The period is read
    from the title when it names one ("Year Ended June 30, 2015", "Period July 1, 2022 through January 9, 2023"; 26 of 78
    statewide-office audits); the Auditor's other titles ("Office of Governor") name no period, and the PDFs are not
    parsed for it, so those audits are linked to everyone in office from January 1 of the year before the release to the
    release date (`link_basis` = `release_window`). That is a bounded guess at the period, not the period: say "in
    office around the time of the audit", never "audited". A mid-term change (Parson, June 2018) has no date in the
    Manual, so both people are credited for the year. Sub-unit audits ("Office of Attorney General - Missouri Office of
    Prosecution Services", "...Medicaid Fraud Control Unit") match the office prefix and count as the office's (#333).
