# Executive business: nominations, treaties, impeachment trials

Executive business is unique to the Senate and makes up most of its roll calls. In our 117th-119th
cache, `PN` rows = 1,477 of 2,555 (58%).

## Nominations

### Normal path

1. The President transmits the nomination. It gets a `PN<number>` for the Congress. One PN can cover
   several people, such as military promotion lists or paired ambassadors.
2. It is referred to the committee of jurisdiction. The committee sends a questionnaire and runs FBI
   and OGE ethics paperwork. Judiciary uses **blue slips** (exceptions.md §18).
3. Hearing, then committee vote, then reported to the **Executive Calendar**.
4. **Floor.** The motion to proceed to executive session to consider a specific nomination is **not
   debatable**, which explains the `On the Motion to Proceed` rows with `PN` in Voteview: 36, all
   agreed. The nomination itself is debatable, so the leader files cloture.
5. **Cloture** (`On the Cloture Motion` with `PN`) needs a majority of those voting: 2013 for most
   nominations, 2017 for SCOTUS. In our data: 664 agreed and 5 rejected. Successful nomination cloture
   has passed with as few as 42 yeas, because only those voting count.
6. **Post-cloture time.** Up to 30 hours for:
   - Supreme Court and circuit judges;
   - Cabinet secretaries and other Executive Schedule Level I positions;
   - certain boards.

   Up to **2 hours** (precedent of 2019-04-03) for district judges and other sub-cabinet nominees.
7. **Confirmation** (`On the Nomination`): majority. In our data, 738 confirmed and 2 rejected:
   - Lisa Gomez (Labor), 49-51 on 2022-06-08. She was later confirmed after renomination
     *(verify)*.
   - Arianna Freeman (3rd Cir.), 47-50 on 2022-09-13, a failed vote in the 50-50 Senate. She was
     confirmed later *(verify)*.
8. **Return.** Under Rule XXXI(6), nominations not acted on are returned to the President at sine die
   adjournment or a recess of more than 30 days, unless UC keeps them in status quo. The President
   must renominate them with a new PN.

### Exceptions and how they are handled

- **Voice votes and UC.** Historically most civilian nominations and nearly all military promotions
  went by UC en bloc. They do not appear in the roll-call data.
- **Holds and blanket objections.** These force every nominee onto the cloture-and-confirmation
  track. That cost two roll calls and up to 2 or 30 hours each, and it caused the 2019 and 2025
  precedent changes.
- **En bloc executive resolutions (since 2025-09-11).**
  1. The majority leader introduces an **executive resolution** (`SRES…`, described as "authorizing
     the en bloc consideration in Executive Session of certain nominations on the Executive Calendar").
     It lists many sub-cabinet executive nominees and ambassadors who have already been reported.
  2. Cloture on that resolution needs only a majority. This was set by overruling the chair:
     `SRES377` decision of chair not sustained 45-53, after a 60-vote cloture attempt and a motion to
     reconsider.
  3. Adopting the resolution confirms everyone on its list.
  4. **Excluded:** Article III judges and Level I (Cabinet-rank) positions under 5 U.S.C. 5312. These
     still go one at a time. Whether a specific listed nominee was "Level I" has been disputed on the
     floor (e.g. the Bennet objection about the ONDCP Director on S.Res.520 *(verify)*).
  5. **In the data.** Look for cloture + `On the Resolution` pairs:

     | Resolution | Cloture | Resolution vote |
     | --- | --- | --- |
     | `SRES377` | 53-43 | 51-44 on 2025-09-15 |
     | `SRES412` | 53-46 | 51-46 on 2025-10-03 |
     | `SRES532` | 51-47 | 52-47 on 2025-12-11 |
     | `SRES690` | 51-46 | 46-45 on 2026-05-11 |
     | `SRES817` | 50-45 | 50-47 on 2026-07-30 |

     **One roll call confirms dozens of people.** Any per-nominee "confirmation vote" model must
     expand these resolutions to their nominee list. That list is in the resolution text on
     congress.gov, not in Voteview.
- **Power-sharing discharge (117th).** Tied committee votes on nominees were discharged by a floor
  motion: 24 `PN` `Motion to Discharge Agreed to` rows, 2021-03 → 2022-08. See exceptions.md §9 and §14.
- **Tie-breaks.** The VP can break ties on nomination cloture and on confirmation. Examples:
  - PN220 (2021-06-22): cloture and confirmation both 50-50.
  - PN117 (2025-01-24, Hegseth): confirmed 50-50 with VP Vance.
- **Recess appointments.** Art. II §3 lets the President fill vacancies during a recess. Since
  *NLRB v. Noel Canning* (2014), a recess of fewer than 10 days is presumptively too short. The Senate
  blocks recess appointments by holding **pro forma sessions** every 3 days. There were none in the
  window.
- **Vacancies Act acting officials.** These are outside Senate procedure, but they explain why some
  offices never get a nominee. The Federal Vacancies Reform Act sets time limits.
- **Supreme Court in the window.**

  | Nominee | Outcome |
  | --- | --- |
  | Garland (2016) | No hearing; the nomination was returned at the end of the 114th. The majority's handling was simply never scheduling it |
  | Gorsuch (2017) | 54-45, after the nuclear option |
  | Kavanaugh (2018) | 50-48 |
  | Barrett (2020) | 52-48 |
  | Jackson (2022) | 53-47 |

## Treaties

- **Path.**
  1. The President transmits the treaty, which gets a `TREATYDOC <congress>-<n>` number.
  2. Referred to Foreign Relations, which reports a **resolution of ratification**, often with
     reservations, understandings, or declarations.
  3. Floor vote on the resolution of ratification: **2/3 of those present and voting**.
     Voteview: `On the Resolution of Ratification` (3 in our data, all agreed).
- **Quirk.** Treaties do **not** die at the end of a Congress. They stay on the Executive Calendar
  (returned to committee) until approved or withdrawn, so a treaty voted in 2022 may have been
  transmitted decades earlier.
- **Example.** NATO accession protocols for Finland and Sweden (Aug 2022, 95-1). Most treaty approval
  happens by division vote, with no roll call.

## Impeachment trials

- **Path.**
  1. The House adopts articles (`HRES`) and appoints managers, who exhibit the articles.
  2. The Senate convenes as a court of impeachment under its *Rules of Procedure and Practice When
     Sitting on Impeachment Trials*. The Chief Justice presides when the President is tried.
     Otherwise the presiding officer is the President pro tempore or another senator.
  3. An organizing resolution (`SRES`) sets the schedule.
  4. Each article is voted separately. Conviction needs **2/3 of those present**.
  5. Disqualification from future office is a separate majority vote, only after conviction.
- **In the data.**
  - `Guilty or Not Guilty` with `bill_number = HRES24`: 2021-02-13, Trump (second trial), 57-43,
    not guilty because 67 were needed.
  - 2021-01-26: a motion to table Sen. Paul's point of order that trying a former President was
    unconstitutional, agreed 55-45 (`bill_number` null).
- **Exceptions and handling.**
  - **Dismissal by point of order (Mayorkas, 2024-04-17).** The Senate sustained points of order that
    each article failed to allege a high crime or misdemeanor (51-49, 51-48), ending the trial with no
    verdict vote. Motions to table those points of order failed 49-51 twice. These rows have a null
    `bill_number` in Voteview. Match on date.
  - **No witnesses vote.** In the 2020 Trump trial, the motion to subpoena witnesses failed 49-51
    (2020-01-31). Acquittal followed on 2020-02-05, 52-48 (abuse) and 53-47 (obstruction). This is
    116th Congress data, not in the cache.
  - **Former officials.** The 2021 trial set by majority vote that the Senate has jurisdiction over a
    former President (56-44 on 2021-02-09 *(verify)*).
