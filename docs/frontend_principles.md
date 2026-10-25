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
- Keep `lookup/districts.json` and the /awards page under the budgets in `frontend/scripts/size-budget.mjs` (checked automatically at the end of `pnpm build`, or on their own with `pnpm sizes`; `MOGOV_SKIP_SIZE_BUDGET=1` skips); do not repeat per-row decorations on hidden blocks
- The build also fails when an official's pay-per-vote year rows do not match their dbt total (`rpt_attendance` and `rpt_attendance_pay` exported from different builds); `MOGOV_SKIP_PAY_YEARS_CHECK=1` (exactly `1`) skips it and logs that it did
- The build also fails when a federal `least_committee_money_share` list has an odd period (a stale `rpt_awards` export that ranks calendar years, which the pages would word as FEC cycles); `MOGOV_SKIP_AWARD_CYCLES_CHECK=1` (exactly `1`) skips it and logs that it did
- Decorative glyphs on links (like "↗") go in an `aria-hidden` span (see `SourceLink`); links that repeat the same text get screen-reader-only context (`sr-only`)
