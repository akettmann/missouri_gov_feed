# Frontend TODO

Goal: help a voter see measurable lean and potential conflicts of interest for their Missouri officials.
Show evidence, not verdicts. Data-side tasks (dbt reporting models, loaders) live in TODO.md.

## Principles (apply to every task)
- No composite "bias score" and no rankings; identical layout for every official regardless of party
- Every fact links to its `source_url`; `match_confidence = medium` rows get a "possible match" badge and a hide toggle
- Render `official_profile.*_status` as a coverage strip so gaps are explicit
- Neutral diverging palette for score scales (no red/blue); party shown as a label
- "Report an error" link on every profile
- Interest-vote views are labeled co-occurrence, not causation

## Phase 0: spikes
- [ ] Build the DB and measure export sizes per official (sets per-page JSON budget)
- [ ] Check whether the Census Geocoder can be called from the browser (CORS); otherwise use map click / geolocation with client-side point-in-polygon
- [ ] Confirm stack: Astro (static build) + Observable Plot, pnpm; build reads `data/exports/*.parquet` with `@duckdb/node-api`
- [ ] Decide audience/hosting (public?) and whether judges are in the MVP

## Phase 1: MVP
- [ ] Scaffold `frontend/` (Astro, pnpm); add eslint, prettier and `astro check` to pre-commit
- [ ] Build-time data layer: read exported parquet, emit one prerendered page plus a small JSON per official
- [ ] Browse/search page: by name, office, district, level
- [ ] Profile header and coverage strip (`official_profile`, `dim_official`)
- [ ] Section A, ideology: indicator values with period, detail and source
- [ ] Section C, money in: top donor organizations, PAC vs individual, size bands, in/out of state (federal), trend by cycle
- [ ] Section D, lobbyist gifts: by principal, category and year
- [ ] Section E, personal interests: current commercial ties (`is_latest_report`), family ties, disclosure filings
- [ ] Methodology page: indicator meanings and limits, match-confidence rules, sources, data freshness
- [ ] Confidence badges, medium-match toggle, "report an error" link
- [ ] Docs: PlantUML diagram of the frontend data flow; build steps in docs/environment.md; refresh steps in docs/sync.md

## Phase 2
- [ ] Find my officials: address / map click / geolocation to districts (needs `census_tiger` loader); lookup runs client-side so addresses never leave the browser
- [ ] Peer strip charts for each indicator, chamber colleagues and party medians (`rpt_indicator_peers`)
- [ ] Section B, party loyalty: unity % and "votes where they broke with their party" list (`rpt_party_breaks`)
- [ ] Compare view: two officials side by side, or official vs chamber/party median
- [ ] Judges' profiles: disclosures, ties, case history (no outcome statistics without a reviewed methodology)

## Phase 3
- [ ] Votes grouped by bill subject (needs bill subjects loader)
- [ ] Interest-vote overlap view (`rpt_interest_vote_overlap`)
- [ ] Balancing scorecard shown next to ACU, if added
- [ ] Deploy static build to a GCS bucket + CDN
