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
- [ ] Site header at phone width (390px): the nav links don't wrap, so "Methodology" runs off the right edge
  and the page scrolls sideways (`layouts/Layout.astro`, every page)
- [ ] Businesses in their district (`fct_jurisdiction_businesses`): the regulated sites in a legislator's, U.S.
  representative's or mayor's area, with the ones that gave to them first (donor name, amount, link to the
  contributions). A house district can hold 1,400 sites, so ship the donor rows plus counts by industry (NAICS),
  not the full list, to stay under the JSON budget. Label the source's limit: EPA-regulated sites only, exact
  name or listed-brand matches only

## Low priority
- [ ] Officials list, past years: people who no longer serve are listed without a link because they have no
  profile. A small page per past officeholder (offices held, years, source links) would let the list link them
- [ ] Officials list: the year control needs JavaScript (it fetches `lookup/officeholders/<year>.json`); without
  it only the current year shows. Static per-year pages would make look-back work without JS
- [ ] Ensure the page looks correct on a wide screen
- [ ] Build a reference that explains what PACs are used for, to hide the sources of money being donated to politicians
