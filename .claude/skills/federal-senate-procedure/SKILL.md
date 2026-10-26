---
name: federal-senate-procedure
description: How a bill, resolution, nomination or treaty moves through the U.S. Senate, the exceptions to that normal path (filibuster and cloture, unanimous consent and holds, reconciliation and the Byrd rule, budget points of order, Congressional Review Act and other fast-track statutes, nuclear-option precedents, en bloc nominations, discharge, vetoes and overrides, impeachment trials, shutdowns and debt limits, tie votes broken by the Vice President) and the procedure the Senate uses to handle each, with the precedents set from the 114th through the 119th Congress (2015-2026). Use when reading or modeling federal Senate roll calls (Voteview `vote_question`, `bill_number`, `vote_result`), explaining why a Senate vote passed with fewer than 60 votes or failed with a majority, classifying Senate votes as procedural or substantive, or reviewing the last ~10 years of Senate history in the missouri_gov_feed repo.
---

# Federal Senate procedure (2015-2026)

Use this skill to explain what a U.S. Senate vote did and where it sat in a measure's life. The House
runs by majority and controls its floor through the Rules Committee. The Senate runs on **unanimous
consent and unlimited debate**. Almost everything that looks odd in the Senate record follows from
one of two things: a single senator can object, and ending debate usually takes 60 votes. The rest is
the list of exceptions, statutory or precedential, where a simple majority is enough.

For the House side, see the `federal-house-procedure` skill. For the whole bill-to-law path across both
chambers, see the `federal-congress` skill (user level). This skill goes deeper on the Senate floor.

## Read these as needed

| File | Read when |
| --- | --- |
| [references/bill_lifecycle.md](references/bill_lifecycle.md) | You need the normal Senate path for legislation, measure types, calendars, thresholds, or the flow diagram |
| [references/exceptions.md](references/exceptions.md) | A vote or event is off the normal path. Each exception lists its trigger, threshold, handling procedure, data signals, and 2015-2026 examples |
| [references/executive_business.md](references/executive_business.md) | The vote is on a nomination (`PN…`), a treaty (`TREATYDOC…`), an en bloc executive resolution, or an impeachment trial |
| [references/timeline_2015_2026.md](references/timeline_2015_2026.md) | You need the party control, precedents, and major events in force in a given Congress |
| [references/voteview_mapping.md](references/voteview_mapping.md) | You are writing SQL or a dbt model over `stg_voteview__rollcalls` / `fct_federal_votes`, or want sanity-check tests |

## Core facts to keep in mind

- **Two calendars, two sessions of business.** Legislation is handled in *legislative session*.
  Nominations and treaties are handled in *executive session* and have their own calendar. In our
  117th-119th data, 1,477 of 2,555 Senate roll calls (58%) are on nominations (`bill_number` like
  `PN%`). A senator's Senate voting record is mostly a confirmation record.
- **Thresholds differ by question, not by importance.**
  - Simple majority of those voting: passage, amendments, nominations, most motions.
  - **3/5 of senators duly chosen and sworn** (60 with no vacancies): cloture on legislation, and
    waiving most Budget Act points of order.
  - **Majority of those voting**: cloture on any nomination (2013, plus SCOTUS in 2017) and on en bloc
    executive resolutions (2025).
  - **2/3 of those present and voting**: cloture on a change to the Standing Rules, a veto override,
    treaty ratification, conviction in an impeachment trial, expulsion, and proposing a
    constitutional amendment.
- **The Vice President breaks ties and Voteview does not count that vote.** A row reading
  `Bill Passed 50-50` (the IRA, 2022-08-07; OBBBA, 2025-07-01) or `Nomination Confirmed 50-50` means
  the VP voted yea. A 50-50 row reading "Rejected" means the VP did not vote or voted nay. Cloture on
  legislation can never be won by a tie-break, because 3/5 counts senators, not those voting. Cloture
  on a nomination needs only a majority of those voting, so it can (PN220, 2021-06-22, agreed 50-50).
- **Cloture is the main event.** In our data there are 751 `On the Cloture Motion` plus 73
  `On Cloture on the Motion to Proceed` votes, against only 67 `On Passage of the Bill`. For contested
  legislation, the cloture vote is the real decision. Passage afterward is often lopsided because
  the outcome is settled.
- **A failed cloture vote is not a rejection of the bill.** The bill stays on the calendar and
  cloture can be filed again. For example, H.R.5371, the fall-2025 continuing resolution, failed
  cloture 13 times (Oct 1-Nov 4, 2025) and then got 60-40 on Nov 9-10. Leaders sometimes vote no on
  purpose so they can move to reconsider later.
- **Most Senate business never gets a roll call.** It passes by unanimous consent or a voice vote.
  Absence from the roll-call data is not absence of action. For the whole action history you need
  bill status (`source: govinfo_billstatus`, a candidate source, not yet loaded).
- **Numbers reset every Congress** for bills and resolutions, and also for `PN` nominations.
  Nominations not acted on are returned to the President at sine die adjournment, or at a recess of
  more than 30 days, unless UC keeps them. Treaties are the exception: they stay pending across
  Congresses. Key on `(congress, bill_number)`.

## Workflow for explaining a Senate vote or a measure's path

1. **Identify the business.** Use the `bill_number` prefix:
   - `PN` → nomination.
   - `TREATYDOC` → treaty.
   - `SRES` with "executive resolution authorizing the en bloc consideration" → en bloc nominations.
   - `HRES` + `Guilty or Not Guilty` → impeachment trial.
   - `SCONRES`/`HCONRES` "setting forth the congressional budget" → budget resolution.
   - `SJRES`/`HJRES` "chapter 8 of title 5" → CRA disapproval.
   - "terminating the national emergency" → National Emergencies Act.
   - "removal of United States Armed Forces" → War Powers.
   - "disapproval of the proposed … sale/export" → Arms Export Control Act.
   - A House-numbered `HR` with an unrelated Senate substitute → a shell bill. Revenue measures must
     originate in the House.
2. **Classify `vote_question`** with `references/voteview_mapping.md`: passage, amendment, cloture,
   motion to proceed, nomination, point of order or appeal, tabling, discharge, veto override,
   inter-chamber, or trial.
3. **Find the governing procedure** in `references/exceptions.md`. Ask what threshold applied, whether
   debate was limited by statute or precedent, and what happens after a failure.
4. **Check the precedents in force** in `references/timeline_2015_2026.md`. Examples:
   - post-cloture time for district judges was 30 hours before April 2019 and 2 hours after;
   - committees were tied 50-50 under the 117th power-sharing agreement;
   - en bloc nominations exist only from September 2025.
5. **State the result in plain words and cite the row** (Voteview URL, or Senate roll call
   `congress-session-number`). If the claim depends on something outside the data, say so. That
   includes UC agreements, House action, a signature, a veto, or a parliamentarian's advice.

## Data coverage caveat

The local cache (`data/cache/voteview/`) holds the **117th-119th** Congresses (2021-2026).
`MOGOV_VOTEVIEW_CONGRESSES` controls the window. A ten-year review needs the **114th, 115th and 116th**
loaded too. Check before you claim anything from our data about 2015-2020, such as the 2017 Gorsuch
precedent, the 2017-18 CRA wave, the 2018-19 shutdown, or the 2020 impeachment trial. The general
history in the references covers those years. The counts in this skill do not.

## Accuracy rules

- Keep counts from our data and general procedural knowledge in separate sentences. Counts come from a
  query, so show the query or model you used. Counts here were computed on 2026-10-25 from
  `HS117-119_rollcalls.csv`.
- Senate procedure lives mostly in **precedent**, not in the text of the Standing Rules. A precedent
  set by overruling the chair binds future proceedings just as firmly as a rule. When unsure, cite
  *Riddick's Senate Procedure*, the CRS reports (e.g. RL30360 on filibusters and cloture, RL30862 on
  reconciliation, R43992 on the CRA), or the Congressional Record for the date. Do not guess.
- Items marked **verify** in the references come from secondary reporting or memory. Confirm them
  against senate.gov, congress.gov, or the Congressional Record before you publish them on the site.
- When explaining a party-line procedural vote, describe what the vote decided, such as "whether to
  end debate" or "whether the chair's ruling stands". Do not describe it as a vote for or against the
  policy.
