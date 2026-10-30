# Frontend principles

Goal: A site to undo all of the intentional and institutional obfuscation and misdirection so that all citizens can get a direct understanding of if a politician is likely working for the citizenry or for themselves, an external benefactor, a corporate overlord, whatever.
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
- RSMo section pages (`/statutes/<section>/`, #840) show the Revisor's text word for word: blank line = paragraph, single line break = line break, tab-separated rows = table, everything else escaped (`lib/statuteText.ts`). The "as of" line says what `loaded_at` is (our pipeline's publish time; the Revisor page may be up to 180 days older, #852), never "copied on". ~44k pages add ~232 MB raw to `dist/`; `pnpm sizes` prints the total and budgets the largest page (`statutes/260.700/`). Without the statute exports the build emits one "not loaded yet" page at `/statutes/not-loaded/`
- `/statutes/` (in the site nav) is the RSMo table of contents: titles in numeral order, each with its chapters and "N of M sections in force" (distinct section numbers, from `rpt_statute_chapters`); chapters the Revisor no longer lists go last. `/statutes/chapter/<chapter>/` lists every section of a chapter, repealed and transferred ones included, in the Revisor's order (`compareSectionIds` in `lib/statuteText.ts`: plain numbers as whole numbers, then Uniform-Code style `400.2A-101` by article; checked against revisor.mo.gov chapter 456). Section pages get a breadcrumb and previous/next links within their chapter (#841). Reaching any section needs no JavaScript; `pnpm sizes` budgets `/statutes/` and the largest chapter page (`statutes/chapter/67/`)
- The build also fails when an `rpt_awards` export lacks `period_kind` (stale), or a `period_kind = 'fec_cycle'` list has an odd period (calendar years the pages would word as FEC cycles); `MOGOV_SKIP_AWARD_CYCLES_CHECK=1` (exactly `1`) skips the odd-period guard and also lets a stale export without `period_kind` build, inferring the kind from award and office (federal `least_committee_money_share` is a cycle) with a warning; leave it unset for real builds
- The build also fails when `fct_committee_posts` chair, co-chair, vice-chair or ranking-minority-member counts do not match the titled rows in `fct_committee_memberships` for an official and session (exports from different builds); `MOGOV_SKIP_COMMITTEE_POSTS_CHECK=1` (exactly `1`) skips it and logs that it did
- Decorative glyphs on links (like "↗") go in an `aria-hidden` span (see `SourceLink`); links that repeat the same text get screen-reader-only context (`sr-only`)
