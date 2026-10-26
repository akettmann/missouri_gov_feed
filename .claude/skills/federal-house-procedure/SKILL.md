---
name: federal-house-procedure
description: How a bill or resolution moves through the U.S. House of Representatives, the exceptions to that normal path (suspension, special rules, discharge petitions, privileged resolutions, vetoes and overrides, motions to recommit, failed rules, Speaker fights, shutdowns, reconciliation), and the procedure the House uses for each, with the rule changes from the 114th through the 119th Congress (2015-2026). Use when reading or modeling federal House roll calls (Voteview `vote_question`, `bill_number`, `vote_result`), explaining what a federal House vote actually decided, classifying votes as procedural or substantive, or reviewing the last ~10 years of House history in the missouri_gov_feed repo.
---

# Federal House procedure (2015-2026)

Use this skill to explain what a U.S. House vote did and where it sat in a bill's life. The House is a
majoritarian chamber. In practice the Speaker and the Rules Committee control what reaches the floor,
and most of what looks odd in the record is one of a small set of exceptions to the normal path.

## Read these as needed

| File | Read when |
| --- | --- |
| [references/bill_lifecycle.md](references/bill_lifecycle.md) | You need the normal path from introduction to public law, bill types, or thresholds |
| [references/exceptions.md](references/exceptions.md) | A vote or event is off the normal path: suspension, rules, discharge, privileged, veto, recommit, ping-pong, reconciliation, CRs, Speaker election, electoral count |
| [references/timeline_2015_2026.md](references/timeline_2015_2026.md) | You need to know which rule was in force in a given Congress (114th-119th) |
| [references/voteview_mapping.md](references/voteview_mapping.md) | You are writing SQL or a dbt model over `stg_voteview__rollcalls` / `fct_federal_votes` |

This skill covers the House floor only. For the Senate (cloture, filibuster, nuclear-option
precedents) and the full path through both chambers, use the user-level `federal-congress` skill if it
is installed. Where the two disagree on a number, the counts here come from a query on our Voteview
cache, so prefer them.

## Core facts to keep in mind

- **A Congress lasts two years** and has two sessions. Bills die at sine die adjournment of the 2nd
  session. Numbering restarts every Congress, so `H.R. 1` in the 118th and the 119th are different
  bills. Always key bills on `(congress, bill_type, number)`.
- **Thresholds.** Most questions need a simple majority of those voting. A **two-thirds** vote of those
  voting is needed for suspension of the rules, a veto override, and expulsion. Proposing a
  constitutional amendment also takes two-thirds. A Speaker needs a majority of members voting *for a
  person*, and "present" does not count. That is why the 15-ballot fight in January 2023 could be won
  at 216.
- **Most roll calls are not passage votes.** In our 117th-119th data (2,905 House roll calls), only
  about 15% are `On Passage`. The rest are amendments, suspensions, rules, motions to recommit,
  previous-question votes, and similar steps. Never count "votes on bill X" without classifying the
  question first.
- **Procedural votes are party-line by design.** `On Ordering the Previous Question` passed 194 of 194
  times and `On Motion to Recommit` failed 201 of 202 times in our data. These votes measure party
  discipline, not policy. Keep them apart from substantive votes in any ideology or "bias" metric.
  (`fct_bias_indicators` currently uses only DW-NOMINATE and does not classify `vote_question`, so
  do not rely on it to separate procedural votes.)
- **A failed vote is not always a defeat of the policy.** A failed suspension usually comes back under
  a rule. A failed rule means the majority lost control of its own floor, which is a notable event in
  itself. A failed veto override is the last step: the measure is dead.

## Workflow for explaining a vote or a bill's path

1. Identify the measure: `congress`, `bill_number` prefix (HR, HRES, HJRES, HCONRES, S, SJRES...).
   A simple resolution (`HRES`) whose text starts "Providing for consideration of..." is a **special
   rule**. The bills it names are the real subject.
2. Classify `vote_question` with the mapping in `references/voteview_mapping.md`: passage,
   amendment, procedural, suspension, rule, inter-chamber, veto override, organizational.
3. If the vote is off the normal path, find the exception in `references/exceptions.md`, including
   its threshold and what happens if it fails.
4. Check `references/timeline_2015_2026.md` for the rules in force in that Congress. Examples: the
   motion to recommit lost its instructions in the 117th, proxy voting ran from May 2020 through the
   117th, and the motion-to-vacate threshold changed in the 118th and again in the 119th.
5. State the result in plain words and cite the source row (Voteview URL or Clerk roll call number).
   If the claim depends on something outside the data, such as Senate action or a presidential
   signature, say so. We do not load bill-status actions yet. That is the candidate source
   `source: govinfo_billstatus`.

## Data coverage caveat

`MOGOV_VOTEVIEW_CONGRESSES` defaults to the recent Congresses, and the local cache holds the
117th-119th. A ten-year review (2015 onward) needs the **114th, 115th, and 116th** loaded too. Check
`data/cache/voteview/` before you claim anything about 2015-2020 from our data.

## Accuracy rules

- Put counts from our data and general procedural knowledge in separate sentences. Counts come from a
  query, and you should show the query or the model you used.
- Rule details change every Congress through the opening rules package (`H.Res. 5` or similar).
  If you are unsure which version applied, say so rather than guess. The authoritative text is the
  *Rules of the House* for that Congress (clerk.house.gov) and the Rules Committee's
  section-by-section summary of the rules package.
- Dates and counts in the timeline that do not come from our data are marked "verify". Confirm them
  against congress.gov or the Clerk before you publish them on the site.
