# Frontend TODO

Goal: help a voter see measurable lean and potential conflicts of interest for their Missouri officials.
Show evidence, not verdicts. Data-side tasks (dbt reporting models, loaders) live in TODO.md.
The Phase 1 MVP is built in `frontend/`; build and refresh steps are in docs/environment.md and docs/sync.md.

## Principles (apply to every task)
- No composite "bias score" and no rankings; identical layout for every official regardless of party
- Every fact links to its `source_url`; `match_confidence = medium` rows get a "possible match" badge and a hide toggle
- Render `official_profile.*_status` as a coverage strip so gaps are explicit
- Neutral diverging palette for score scales (no red/blue); party shown as a label
- "Report an error" link on every profile
- Interest-vote views are labeled co-occurrence, not causation
- Keep each official's JSON under the 100 KB gzipped budget (`pnpm sizes` after every data refresh)

## Open decisions
- [ ] Audience/hosting (public?) and whether judges stay in (they get profiles today; ideology/votes show "not applicable")
- [ ] ACU: it no longer appeared in the latest export. If it's dropped for good, remove it from
  `frontend/src/lib/indicators.ts` (methodology page) and drop the Phase 3 balancing-scorecard item

## Follow-ups from the MVP
- [ ] FEC size bands: confirm whether `fct_federal_donor_summary` `by_size` bucket 0 includes unitemized money
  (the dbt docs say itemized only, but Hawley's under-$200 band is $8M+); fix the docs or the chart note
- [ ] State size bands: `rpt_donor_rollup` has no per-contribution size, so only federal officials get a size view;
  add a size-band column or a small `rpt_donor_size` model
- [ ] `rpt_donor_rollup.donor_name` is an employer for individuals ("none", "retired", ...); the frontend leaves
  individuals out of "Top donor organizations" for now

## Phase 2
- [ ] Census Geocoder spike: can it be called from the browser (CORS)? Otherwise map click / geolocation with
  client-side point-in-polygon
- [ ] Find my officials: address / map click / geolocation to districts (needs `census_tiger` loader); lookup runs
  client-side so addresses never leave the browser
- [ ] Peer strip charts for each indicator, chamber colleagues and party medians (`rpt_indicator_peers`, built)
- [ ] Section B, party loyalty: unity % and "votes where they broke with their party" list (`rpt_party_breaks`, built)
- [ ] Attendance per session vs chamber (`rpt_attendance`, built)
- [ ] Compare view: two officials side by side, or official vs chamber/party median
- [ ] Judges' profiles: disclosures, ties, case history (no outcome statistics without a reviewed methodology)

## Phase 3
- [ ] Votes grouped by bill subject (needs bill subjects loader)
- [ ] Interest-vote overlap view (`rpt_interest_vote_overlap`)
- [ ] Balancing scorecard shown next to ACU, if added
- [ ] Deploy static build to a GCS bucket + CDN
