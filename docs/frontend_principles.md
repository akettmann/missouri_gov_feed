# Frontend principles

Goal: help a voter see measurable lean and potential conflicts of interest for their Missouri officials.
Show evidence, not verdicts. The MVP is built in `frontend/`; build and refresh steps are in docs/environment.md
and docs/sync.md. Open work is tracked in GitHub issues labeled `Frontend`.

## Principles (apply to every change)

- No composite "bias score" or judgment calls; identical layout for every official regardless of party. Rankings
  and awards are fine when each one ranks a single measured number (attendance %, PAC dollars, party unity %) and
  shows that number with its source
- Every fact links to its `source_url`; `match_confidence = medium` rows get a "possible match" badge and a hide toggle
- Render `official_profile.*_status` as a coverage strip so gaps are explicit
- Neutral diverging palette for score scales (no red/blue); party shown as a label
- "Report an error" link on every profile
- Interest-vote views are labeled co-occurrence, not causation
- Keep each official's JSON under the 100 KB gzipped budget (`pnpm sizes` after every data refresh)
- Keep `lookup/districts.json` and the /awards page under the budgets in `frontend/scripts/size-budget.mjs` (also checked by `pnpm sizes`); do not repeat per-row decorations on hidden blocks
