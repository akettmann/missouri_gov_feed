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

## Medium priority

## Low priority
- [ ] Find my officials on a wide screen: before a lookup the results column (right two fifths) is empty
  beside the map; a short "your officials will appear here" placeholder would balance it
- [ ] PAC reference (`/pacs/`): Missouri's statewide contribution limit is quoted as $2,825 with a proposed
  $3,225 (rule filed July 9, 2026). Update the figure once the Secretary of State's rule takes effect
- [ ] Profiles: when a top donor is a Missouri committee, show that committee's own top donors one hop back
  (needs a committee-to-committee rollup in dbt; see TODO.md), so pass-through PACs aren't a dead end
- [ ] Businesses in their area: when "Hide possible matches" hides every donor row, the donor table is left with
  only its header; say "all matched donors here are possible matches" instead (as the charts do)
- [ ] Businesses in their area: offer the full site list per district (all ~1,400 in a house district) as a
  separate per-district download or page, outside the per-official JSON budget
- [ ] Compare page: add a businesses-in-their-area row (donor companies with sites in the area, total sites)
- [ ] Officials list, past years: people who no longer serve are listed without a link because they have no
  profile. A small page per past officeholder (offices held, years, source links) would let the list link them
- [ ] Officials list: the year control needs JavaScript (it fetches `lookup/officeholders/<year>.json`); without
  it only the current year shows. Static per-year pages would make look-back work without JS
