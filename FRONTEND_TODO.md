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
- [ ] When going public (the site will be public; development stays local for now): create the bucket
  (docs/environment.md "Publishing to Google Cloud Storage") and run `MOGOV_SITE_BUCKET=... pnpm deploy:gcs`;
  the script and docs are ready
