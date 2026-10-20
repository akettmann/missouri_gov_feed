# Frontend TODO

Goal: help a voter see measurable lean and potential conflicts of interest for their Missouri officials.
Show evidence, not verdicts. Data-side tasks (dbt reporting models, loaders) live in TODO.md.
The MVP is built in `frontend/`; build and refresh steps are in docs/environment.md and docs/sync.md.

## Principles (apply to every task)
- No composite "bias score" or judgment calls; identical layout for every official regardless of party. Rankings
  and awards are fine when each one ranks a single measured number (attendance %, PAC dollars, party unity %) and
  shows that number with its source
- Every fact links to its `source_url`; `match_confidence = medium` rows get a "possible match" badge and a hide toggle
- Render `official_profile.*_status` as a coverage strip so gaps are explicit
- Neutral diverging palette for score scales (no red/blue); party shown as a label
- "Report an error" link on every profile
- Interest-vote views are labeled co-occurrence, not causation
- Keep each official's JSON under the 100 KB gzipped budget (`pnpm sizes` after every data refresh)

## High priority
- [ ] Decide audience/hosting (public?) and whether judges stay in (they get profiles today; ideology/votes show
  "not applicable")
- [ ] Decide on address search for /find/ (today: device location or a map click only). The Census Geocoder
  sends no CORS header, so a browser can reach it only by JSONP: that runs Census-hosted script on our page and
  sends the typed address to the Census Bureau. Options: accept that with a notice; geocode through a small proxy
  of our own; or ship a ZIP-code centroid table (coarse: a ZIP can span several districts)

## Medium priority
- [ ] State size bands: `rpt_donor_rollup` has no per-contribution size, so only federal officials get a size view;
  add a size-band column or a small `rpt_donor_size` model
- [ ] `rpt_donor_rollup.donor_name` is an employer for individuals ("none", "retired", ...); the frontend leaves
  individuals out of "Top donor organizations". A "top employers of individual donors" view needs those values
  cleaned or excluded in dbt first

## Low priority
- [ ] Votes grouped by bill subject (bill subjects from `mo_senate_topics`)
- [ ] Interest-vote overlap view (`rpt_interest_vote_overlap`)
- [ ] Deploy static build to a GCS bucket + CDN
- [ ] Add "Awards" such as "Worst Attendance", "Most Money from PACs", "Always Votes with the Party", each award can be by year and lifetime, implement the opposite positive version as well.
