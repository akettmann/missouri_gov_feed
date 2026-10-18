# missouri-gov-feed

A data pipeline that profiles every current Missouri public official: statewide executives, the
General Assembly, the congressional delegation, tracked mayors, and state and federal judges in Missouri.
Python loaders fetch public records; dbt (DuckDB locally) turns them into one profile per official.

```
uv sync
uv run mogov run          # stage-1 loaders -> dbt build -> stage-2 loaders -> dbt build
uv run mogov export       # marts -> data/exports/*.csv   (--format parquet also works)
```

Other commands: `mogov list` (loaders), `mogov load <loader> ...`, `mogov build [dbt args]` (for example `-s +fct_votes`).

## What you get (dbt `marts` schema)

| Category requested | Model | Sources |
|---|---|---|
| Officials | `dim_official`, `official_profile` | Open States, MO House XML, congress-legislators, statewide seed, Official Manual, FJC |
| Forced disclosures | `fct_disclosures` | U.S. House Clerk (annual reports and trades), Senate eFD, federal judges' AO-10 reports (CourtListener) |
| Voluntary disclosures | `fct_voluntary_disclosures` | hand-curated `dbt/seeds/voluntary_disclosures.csv` (no feed exists) |
| Donations to / from them | `fct_campaign_finance`, `fct_federal_donor_summary`, `fct_lobbyist_gifts` | FEC bulk + API; MEC via the Accountability Project mirror (2011–2022); MEC direct (opt-in) |
| Biases | `fct_bias_indicators` | DW-NOMINATE, Shor-McCarty, ACU ratings, party-unity computed from votes |
| Family in company leadership | `fct_family_ties` | Wikidata relatives and the organizations they lead; spouse/dependent items on disclosures |
| Voting history | `fct_votes` | MO House roll-call PDFs (2023+), MO Senate journals (2023+), Voteview (Congress) |
| Past offices | `fct_office_history` | Open States, congress-legislators, Wikidata, FJC, CourtListener, Official Manual bios |
| Commercial ventures and relationships | `fct_commercial_ties` | disclosure positions, income, compensation and agreements; Wikidata |
| Case history (judges and lawyers, current or former) | `fct_legal_careers`, `fct_case_history` | bios, Wikidata, FJC; CourtListener opinions |

`official_profile` has a `*_status` column per category: `available`, `none found`, `not applicable`, or
`not public` (with how to obtain it), so gaps are explicit rather than silent.

Name-matched records carry a `match_confidence` column. Read medium-confidence matches with care.

## Configuration (`.env`, gitignored)

| Variable | Effect |
|---|---|
| `FEC_API_KEY` | api.data.gov key. Adds donor aggregates and leadership-PAC lookups (DEMO_KEY is ~10 calls/hour). |
| `MOGOV_CONTACT` | Email or URL put in the User-Agent. Required by Wikidata; enables the `wikidata` loader. |
| `MOGOV_ACCEPT_SENATE_EFD_TERMS=1` | Accept the Senate eFD use statement; enables `senate_efd`. |
| `COURTLISTENER_TOKEN` | Free courtlistener.com token. Adds case outcomes and lifts the 5 requests/minute limit. |
| `MOGOV_CL_MAX_QUERIES`, `MOGOV_CL_PAUSE` | Case-search cap and pacing. Without a token the defaults are 60 searches per run, 15 s apart; results are cached for 30 days, so repeated runs make progress. |
| `MOGOV_MEC_OPT_IN=1`, `MOGOV_MEC_USER_AGENT` | Enables direct MEC campaign-finance and lobbying exports (2023+). MEC's robots.txt disallows these pages and its bot protection rejects non-browser clients; see `src/mogov/loaders/mec.py`. |
| `MOGOV_FEC_INDIV=1` | Also land FEC individual contributions (~2.3 GB per cycle). |
| `MOGOV_*_YEARS`, `MOGOV_HOUSE_SESSIONS`, `MOGOV_FEC_CYCLES`, ... | Coverage windows (see each loader's header). |

## Layout

```
src/mogov/loaders/   one module per source; lands raw data only (data/raw/<table>.parquet)
src/mogov/http.py    cached, polite HTTP (data/cache/)
dbt/models/staging   one model per raw table: typing and renaming
dbt/models/intermediate  identity resolution (vote tokens -> people, committees -> officials, ...)
dbt/models/marts     the per-official facts above
dbt/macros/compat    adapter.dispatch macros (JSON, regex, dates, casts) so models are backend-portable
```

Rules for contributors:

- Python only extracts and lands data; every transformation is dbt.
- dbt SQL must stay portable. Use `mogov.*` and `dbt.*` macros, not DuckDB-only syntax.
- pre-commit runs ruff and sqlfluff (`uv run pre-commit install`).

## Known gaps (data not obtainable online)

- **Missouri personal financial disclosure statements** (legislators, statewide officers, judges) are released only on written Sunshine Law (RSMo 610) request: from MEC for officials, from the Clerk of the Supreme Court for judges.
- **MEC campaign finance after 2022** requires the opt-in `mec` loader.
- **MO Secretary of State business registry** (company officers) sits behind bot protection with no bulk export. Family and business ties therefore come from Wikidata and disclosures only.
- **Case.net** (state trial courts) prohibits automated access under Court Operating Rule 2.02. Case history covers appellate and federal opinions in CourtListener; its Missouri state opinions end in 2025.
- **State roll calls** are loaded for 2023–2026 by default. Widen the window with `MOGOV_HOUSE_SESSIONS` (House PDFs go back to 2014) and `MOGOV_SENATE_YEARS`.
