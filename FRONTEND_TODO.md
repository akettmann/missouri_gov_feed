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
- [ ] Officials list: by default, show only the people holding office in the current year (not past
  officeholders), with a way to look back at other years. Note: `dim_official` holds only sitting officials
  today, so other years need past officeholders (`fct_office_history`) brought into the list
- [ ] Officials list: replace the Level and Office dropdowns with picture tiles to pick from (for example the
  Capitol for the legislature, a gavel for courts, the U.S. Capitol for Congress, a city hall for mayors),
  each labeled in text so the choice doesn't rely on the image
- [ ] Businesses in their district (`fct_jurisdiction_businesses`): the regulated sites in a legislator's, U.S.
  representative's or mayor's area, with the ones that gave to them first (donor name, amount, link to the
  contributions). A house district can hold 1,400 sites, so ship the donor rows plus counts by industry (NAICS),
  not the full list, to stay under the JSON budget. Label the source's limit: EPA-regulated sites only, exact
  name or listed-brand matches only

## Low priority
- [ ] Ensure the page looks correct on a wide screen
- [ ] PAC reference (`/pacs/`): Missouri's statewide contribution limit is quoted as $2,825 with a proposed
  $3,225 (rule filed July 9, 2026). Update the figure once the Secretary of State's rule takes effect
- [ ] Profiles: when a top donor is a Missouri committee, show that committee's own top donors one hop back
  (needs a committee-to-committee rollup in dbt; see TODO.md), so pass-through PACs aren't a dead end
