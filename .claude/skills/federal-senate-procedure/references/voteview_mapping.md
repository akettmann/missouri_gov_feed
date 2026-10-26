# Senate roll calls in Voteview: classification, quirks, sanity tests

Models: `stg_voteview__rollcalls` (all chambers) and `fct_federal_votes` (Missouri members). Filter
`chamber = 'Senate'`. Counts below are from the 117th-119th cache (2,555 Senate roll calls), computed
2026-10-25.

## `vote_question` → category

| `vote_question` | n | Category | What a "yes" decides | Threshold |
| --- | --- | --- | --- | --- |
| On the Cloture Motion | 751 | cloture | End debate on the pending question (bill, amendment, nomination, en bloc resolution) | 3/5 sworn for legislation. Majority for `PN` and en bloc `SRES` (2025-09-11+) |
| On the Nomination | 740 | nomination | Confirm | majority |
| On the Amendment | 368 | amendment | Adopt the amendment | majority, unless UC set 60 |
| On the Motion | 187 | procedural (mixed) | Read `vote_desc` / `dtl_desc`: motions to waive (3/5), concur, commit, instruct, and so on | varies |
| On the Motion to Proceed | 138 | motion to proceed | Take up the measure. With `PN` it is a non-debatable move to executive session | majority |
| On Cloture on the Motion to Proceed | 73 | cloture | End debate on taking up the measure | 3/5 sworn |
| On the Joint Resolution | 68 | passage | Pass the `SJRES`/`HJRES`, mostly CRA and NEA | majority, or 2/3 for a constitutional amendment |
| On Passage of the Bill | 67 | passage | Pass the bill | majority |
| On the Motion to Discharge | 60 | discharge | Bypass committee: statutory (CRA, AECA, ICA) or 117th power-sharing | majority |
| On the Motion to Table | 38 | procedural | Kill the pending amendment, motion, appeal, or point of order | majority |
| On the Resolution | 11 | passage | Adopt the `SRES`. In 2025+ usually an **en bloc nominations** resolution | majority |
| On the Concurrent Resolution | 8 | passage | Budget resolution or War Powers §5(c) | majority |
| On the Point of Order | 7 | point of order | Sustain the point of order ("Well Taken" / "Sustained") | majority |
| On the Motion to Recommit | 7 | procedural | Commit with instructions, often in a vote-a-rama | majority |
| On the Motion to Adjourn | 7 | procedural | Adjourn | majority |
| On the Decision of the Chair | 5 | appeal | The chair's ruling stands. **"Not Sustained" = new precedent** | majority |
| On Overriding the Veto | 5 | veto override | Override | 2/3 present and voting |
| On the Motion for Attendance | 3 | procedural | Compel attendance | majority |
| On the Resolution of Ratification | 3 | treaty | Consent to ratification | 2/3 present and voting |
| On the Motion to Reconsider | 3 | procedural | Reconsider a prior vote. Setup for precedent changes | majority |
| On the Objection | 2 | electoral count | Sustain an objection to electoral votes | majority |
| On the Motion to Refer | 2 | procedural | Refer to committee | majority |
| On the Conference Report | 1 | inter-chamber | Adopt the conference report | majority (cloture 3/5) |
| Guilty or Not Guilty | 1 | impeachment | Convict | 2/3 present |

**Substantive vs procedural.** For ideology or "voting record" summaries, treat these as
**substantive**: passage, nomination, amendment, override, treaty, guilty, and en bloc resolution
votes. Treat cloture as **semi-substantive**: for filibustered bills it *is* the decisive vote, so
report it, but label it "vote to end debate". Everything else is **procedural** and largely
party-line (point of order, appeal, table, motion to proceed on `PN`, adjourn, attendance,
reconsider).

## Quirks

- **VP tie-breaks are invisible.** `yea_count = nay_count` with a positive result means the VP voted
  yea. Do not test "passed ⇒ yea > nay" without allowing ties.
- **Null `bill_number`** (17 rows): trial-procedure votes (the 2021 Paul point of order, the 2024
  Mayorkas points of order) and some procedural motions. Join on date and description, not bill.
- **`bill_number` reflects the vehicle, not the content.** Shell bills (H.R.2882 for FY2024 approps,
  H.R.3684 for IIJA, H.R.5376 for IRA) mean the title is misleading. Use `vote_desc` / `dtl_desc`.
- **`vote_desc` on an amendment vote** is the amendment's purpose ("To improve the bill.", "In the
  nature of a substitute.").
- **One en bloc resolution confirms many nominees.** Voteview has no per-nominee row for them.
- **Multi-person `PN`s.** Paired ambassadors and military lists share one PN.
- **Congress-scoped numbering.** `PN117` in the 119th is not `PN117` in the 117th. Key on
  `(congress, bill_number)`.
- **`vote_result` vocabulary** is a closed set per question (e.g. "Decision of Chair Not Sustained",
  "Point of Order Well Taken", "Veto Sustained"). An `accepted_values` test catches new wording.
- **Cache window.** Only the 117th-119th are cached. Set `MOGOV_VOTEVIEW_CONGRESSES` to include
  114-116 for a ten-year review.

## Example classification SQL (portable dbt)

```sql
select
    congress,
    rollnumber,
    vote_date,
    bill_number,
    vote_question,
    vote_result,
    case
        when vote_question like '%Cloture%' then 'cloture'
        when vote_question = 'On the Nomination' then 'nomination'
        when vote_question = 'On the Resolution'
            and lower(vote_desc) like '%en bloc consideration%' then 'en_bloc_nominations'
        when vote_question in (
            'On Passage of the Bill', 'On the Joint Resolution',
            'On the Resolution', 'On the Concurrent Resolution', 'On the Conference Report'
        ) then 'passage'
        when vote_question = 'On the Amendment' then 'amendment'
        when vote_question = 'On Overriding the Veto' then 'veto_override'
        when vote_question = 'On the Resolution of Ratification' then 'treaty'
        when vote_question = 'Guilty or Not Guilty' then 'impeachment'
        when vote_question in ('On the Decision of the Chair', 'On the Point of Order') then 'precedent'
        when vote_question = 'On the Motion to Discharge' then 'discharge'
        else 'procedural'
    end as senate_vote_category,
    yea_count = nay_count as is_tie_vp_decides
from {{ ref('stg_voteview__rollcalls') }}
where chamber = 'Senate'
```

Keep this out of DuckDB-only syntax (no `ilike`, no `regexp_matches`). Use `lower(...) like` or
dbt cross-db macros, per the repo's portability rule.

## Sanity-check tests ("we have never seen…")

Write these as dbt data tests over fixed rows, or as unit tests with deliberately broken rows that
must fail. Observed bounds are from the 117th-119th:

1. **Legislative cloture below 60 never succeeds.** Cloture agreed with `yea_count < 60` occurs only
   when `bill_number like 'PN%'`, or for an en bloc executive resolution on or after 2025-09-11.
   Observed: the 5 en bloc SRES rows are the only non-PN exceptions.
2. **2/3 questions.** `Veto Overridden`, `Resolution of Ratification Agreed to`, and `Guilty` need
   `yea_count * 3 >= (yea_count + nay_count) * 2`.
3. **No more than ~40 Senate roll calls in a day.** Observed max: 37 on 2022-08-07 (IRA vote-a-rama).
   A day above 50 is almost certainly a load duplication.
4. **Ties.** `yea_count = nay_count` with a positive result implies a VP vote. Flag those that fall
   on a cloture question for legislation: impossible.
5. **Totals.** `yea_count + nay_count <= 100`.
6. **`vote_result` accepted values** per `vote_question` (closed vocabulary above).
7. **Nomination rejections are rare.** More than ~5 `Nomination Rejected` per Congress is worth a
   look. Observed: 2 in three Congresses.
