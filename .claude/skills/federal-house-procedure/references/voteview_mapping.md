# Classifying House roll calls in our data

Models: `stg_voteview__rollcalls` (all members of both chambers) and `fct_federal_votes` (Missouri
delegation). Filter `chamber = 'House'`. Key columns are `congress`, `rollnumber`, `vote_date`,
`bill_number` (for example `HR2670`, `HRES757`, `HJRES30`, or null), `vote_question`, `vote_desc`
(title), `vote_result`, `yea_count`, and `nay_count`.

## vote_question → category

The counts come from the 117th-119th cache (2,905 House roll calls).

| Category | `vote_question` patterns | n | Threshold | Notes |
| --- | --- | --- | --- | --- |
| passage | `On Passage` | 448 (11 failed) | majority | Final House action under a rule |
| suspension | `%Suspend the Rules%` | 791 | 2/3 | Includes "Pass", "Agree", "Concur", and en bloc "Certain Bills" variants. 23 failed |
| amendment | `On Agreeing to the Amendment%` | 830 (520 failed) | majority | Committee of the Whole. Substantive, but often messaging |
| rule | `On Agreeing to the Resolution%` where `vote_desc like 'Provid%consideration%'` | 200 (12 failed) | majority | Procedural. Check the bills it names |
| previous_question | `On Ordering the Previous Question` | 194 | majority | Procedural and party-line. 194/194 passed |
| recommit | `On Motion to Recommit`, `On Motion to Commit%` | 211 (210 failed) | majority | Procedural and party-line since the 117th |
| resolution_other | `On Agreeing to the Resolution%`, other `vote_desc` | 83 (14 failed) | majority (2/3 to expel) | Censure, expulsion, contempt, impeachment, war powers `HCONRES` |
| inter_chamber | `On Motion to Concur%`, `On Concurring%`, `On Retaining%`, `%Conference%`, `On Motion to Instruct Conferees` | 33 | majority | Resolving differences with the Senate |
| veto_override | `Passage, Objections of the President%` | 9 | 2/3 | All failed in the cache |
| discharge | `%Discharge%` | 6 | majority | 119th only |
| privileged_disposal | `On Motion to Table%`, `Table Motion%`, `On Motion to Refer`, `On Motion to Reconsider` | 45 | majority | Often how censure, impeachment, and vacate resolutions are killed. Check `vote_desc` |
| organizational | `Election of the Speaker`, `On Motion to Adjourn`, `On Consideration of the Resolution`, `On Agreeing to the Objection` | 55 | varies | Speaker rows have a surname in `vote_result` |

Notes:

- `vote_result` values are `Passed`, `Failed`, `Agreed to`, or a **surname** for Speaker ballots (sometimes with the state, for example "Johnson (LA)").
  Normalize these before computing pass rates.
- `bill_number` is null for Speaker elections, adjournment, and electoral count objections.
- `vote_desc` can contain mojibake curly quotes (cp1252 ↔ UTF-8). Do not use it as a join key.
- A "rule" row's `bill_number` is the `HRES`. To link a rule to the bills it governs, parse
  `vote_desc` ("Providing for consideration of the bill (H.R. 4365)...") or, better, use bill-status
  data once `govinfo_billstatus` exists.
- The 2/3 threshold is of those voting. When you check `vote_result` against `yea_count`/`nay_count`,
  use `yea >= 2 * nay` for suspension and override rows, not a majority.

## Sanity-check test ideas (dbt, fixed-row unit tests)

- Every suspension or override row with `vote_result = 'Passed'` has `yea_count >= 2 * nay_count`.
- Every non-suspension, non-override `Passed` row has `yea_count > nay_count`. Exclude Speaker rows.
- No more than ~60 House roll calls on one `vote_date`. The highest day in the cache has 52.
- `yea_count + nay_count <= 441` (435 voting members plus 6 delegates; delegates cannot vote on
  passage, but voted in the Committee of the Whole in some Congresses).
- Speaker-election rows exist only in the first days of a Congress or right after a vacancy.

Per project rules, build these as unit tests on fixed input rows. Show each one fails on broken logic
(for example a 2/3 check written as a majority check), not just that it passes on current data.

## Classification sketch (portable SQL)

```sql
case
    when vote_question like 'Passage, Objections of the President%' then 'veto_override'
    when vote_question like '%Suspend the Rules%' then 'suspension'
    when vote_question like '%Discharge%' then 'discharge'
    when vote_question = 'On Ordering the Previous Question' then 'previous_question'
    when vote_question like 'On Motion to Recommit%' or vote_question like 'On Motion to Commit%' then 'recommit'
    when vote_question like 'On Agreeing to the Amendment%' then 'amendment'
    when vote_question like 'On Agreeing to the Resolution%'
         and vote_desc like 'Provid%consideration%' then 'rule'
    when vote_question like 'On Agreeing to the Resolution%' then 'resolution_other'
    when vote_question = 'On Passage' then 'passage'
    when vote_question like '%Concur%' or vote_question like 'On Retaining%'
         or vote_question like '%Conference%' or vote_question like '%Conferees%' then 'inter_chamber'
    when vote_question like '%Table%' or vote_question in ('On Motion to Refer', 'On Motion to Reconsider')
        then 'privileged_disposal'
    else 'organizational'
end
```

Put this in a seed or macro, not copy-pasted SQL, if a model starts using it.
