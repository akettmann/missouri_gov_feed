# Exceptions to the normal path, and how the House handles each

Each entry covers what the exception is, why it is used, the procedure, what happens when it fails,
and how it shows up in Voteview (`vote_question`). Counts are from our cached 117th-119th House roll
calls (2,905 votes), unless marked "verify".

## 1. Suspension of the rules (the most common shortcut)

- **What:** Under Rule XV, a motion to suspend the rules and pass a bill skips the Rules Committee,
  and often committee markup. Allowed on Monday through Wednesday, and on other days by a rule or
  unanimous consent.
- **Procedure:** 40 minutes of debate, no floor amendments (the motion can pass the bill "as
  amended" with text the manager has already chosen), no motion to recommit, and **2/3 of those
  voting**. Many pass by voice vote, so they leave no roll call.
- **If it fails:** The bill is not dead. The majority can bring it back under a special rule, which
  needs only a simple majority. A failed suspension of a bill the majority wants is a signal of
  bipartisan opposition, or of a majority that cannot pass rules.
- **Data:** `On Motion to Suspend the Rules and Pass[, as Amended]`, `...and Agree`,
  `...and Concur in the Senate Amendment`, `...Pass Certain Bills` (en bloc). 791 suspension roll
  calls, of which 23 failed. In the 118th, leadership also passed major bills such as appropriations
  and the conference report on the FY2024 NDAA (H.R. 2670, Dec. 14, 2023) under suspension. It did
  so because hard-liners blocked the rules, so it needed Democratic votes.

## 2. Special rules (Rules Committee resolutions)

- **What:** An `H.Res.` that sets debate terms. The forms are open, structured, or closed, and
  rules can waive points of order (for example budget or CUTGO points of order), self-execute
  amendments, "deem" a measure passed, or combine several bills in one rule.
- **Procedure:** Two votes, `On Ordering the Previous Question` then `On Agreeing to the Resolution`.
  Defeating the previous question would let the minority offer an amendment to the rule. That never
  happened in our data (194 of 194 passed).
- **Failure:** If the rule fails, the underlying bills cannot come up under it. Leadership pulls the
  bill, rewrites the rule, or moves the bill under suspension. Failed rules were historically very
  rare. Recorded rule votes (`HRES` "Providing for consideration...") break down as follows. In the
  117th, 0 of 72 failed. In the 118th, 7 of 62 failed: H.Res. 463, 680, 712, 869, 947, 994, 1125. In
  the 119th, 5 of 59 failed: H.Res. 282, 580, 1042, 1175, 1398. Examples include H.Res. 463 (June
  2023, REINS Act), H.Res. 712 (Sept. 2023, Defense appropriations), H.Res. 1125 (Apr. 2024, FISA
  reauthorization), and H.Res. 580 (July 2025, FY2026 Defense appropriations).
- **Self-executing rules / "deem and pass":** Adopting the rule changes bill text or treats another
  measure as passed, with no separate recorded vote on the change. When you see a passage vote on a
  bill whose text changed between committee and floor, check the rule.
- **Same-day authority / "martial law" rules:** These waive the Rule XIII requirement that a rule lie
  over one day, so leadership can move a measure the day it is reported. They are common near
  shutdown and debt-limit deadlines.

## 3. Motion to recommit (MTR)

- **What:** The minority's last motion before passage, sending the bill back to committee.
- **Before the 117th:** It could carry instructions to report back "forthwith" with an amendment, so
  in effect it was a final minority amendment, often a "gotcha" vote.
- **From the 117th (H.Res. 8, Jan. 2021):** It has no instructions, is not debatable, and simply
  sends the bill back to committee. Republican majorities in the 118th and 119th kept this form.
- **Data:** `On Motion to Recommit` failed 201 of 202 times. The one success was H.R. 2925 (May 1,
  2024). A passed MTR without instructions sends the bill back to committee, and the bill comes back
  only if the committee reports it again. Treat MTR as a party-line procedural vote.

## 4. Discharge petition (bypassing leadership)

- **What:** Under Rule XV cl. 2, if a measure has been in committee for 30 legislative days, 218
  members can sign a petition to discharge it. The usual target is the Rules Committee, holding a
  special rule that a member has written to bring up the real bill.
- **Procedure:** Once it has 218 signatures, it is placed on the Discharge Calendar. After 7
  legislative days, any signer can call it up on the 2nd or 4th Monday. The House then votes
  `On Motion to Discharge`, and if that passes, takes up the rule and then the bill.
- **Countermoves:** Leadership can table the motion, or turn it off with a provision in another rule
  that declares the petition void or "deems" the motion disposed of. Leadership can also pass the
  bill first on its own terms.
- **Data:** Six discharge-related roll calls, all in the 119th. Five `On Motion to Discharge` passed
  (H.Res. 432, 780, 965, 518, 1140 in Dec. 2025–June 2026), and one `On Motion to Table the Motion
  to Discharge Committee` (H.J.Res. 117, Sept. 2025). In the 119th the discharge petition went from
  a rare threat to a working tool for narrow-majority coalitions.
- **A petition can succeed without a discharge roll call.** Once a petition reaches 218 signatures,
  leadership often brings the bill up itself, usually under suspension. That happened with the
  Social Security Fairness Act (118th, Nov. 2024) and the Epstein Files Transparency Act (119th,
  Nov. 2025) (verify both). Counting `On Motion to Discharge` rows therefore undercounts successful
  petitions. You need petition data from the Clerk's discharge petition pages.

## 5. Privileged business

Some measures can be called up without a rule, because a rule of the House or a statute makes them
privileged.

- **Questions of the privileges of the House (Rule IX):** These are resolutions about the House's
  dignity or integrity, such as censure, expulsion, reprimand, and the **motion to vacate the
  chair**. Any member can offer one. The Speaker must schedule it within 2 legislative days, and it
  is often met with a motion to table or refer. Data: `On Motion to Table`, `On Motion to Refer`.
  An expulsion resolution needs 2/3. For example, H.Res. 773 (Nov. 2023, Santos) failed, and a later
  expulsion succeeded on Dec. 1, 2023 (verify the roll call).
- **Impeachment** resolutions are privileged. A member can force a vote, which is usually answered
  with a motion to table or refer.
- **Statutory expedited procedures:**
  - **Congressional Review Act** joint resolutions disapprove agency rules. They are privileged in
    the Senate and normally go through a rule in the House. If the President signs one, the
    regulation cannot be reissued "in substantially the same form". Most CRA resolutions passed
    under a split government were vetoed, and the overrides failed (see §8).
  - **War Powers Resolution §5(c)/§7:** These concurrent resolutions directing removal of forces get
    expedited consideration. Data: 10 failed `HCONRES` war powers votes in the 118th-119th.
  - **National Emergencies Act** joint resolutions to end an emergency also have expedited rights.
    Leadership has used rules to "turn off" the clock, for example H.J.Res. 117 in the 119th.
  - **D.C. Home Rule Act** disapproval resolutions (for example H.J.Res. 42, 118th, vetoed).
- **Conference reports, Senate amendments, and vetoed bills** are privileged once they are
  available.

## 6. Resolving differences with the Senate

- **Amendment exchange ("ping-pong"):** The usual path today. The House votes
  `On Motion to Concur in the Senate Amendment` or `...with an Amendment`, often under suspension.
  Deep nesting such as "Senate Adt to the House Adt to the Senate Adt" appears in our data.
  Exchanges are limited to two degrees of amendment per chamber.
- **Conference committee:** Now rare. The House votes `On Motion to go to Conference`, conferees are
  appointed, the minority may offer `On Motion to Instruct Conferees`, which is non-binding, and the
  conference report cannot be amended. Data: H.R. 2670 (FY2024 NDAA, 2023) went to conference, and
  there was even a vote `On Closing Portions of the Conference`.
- **Division of the question:** On a large Senate amendment, the House can vote by division, which
  shows up as `On Retaining Title ...` and `On Concurring in Senate Amdt with Amdt (Divisions ...)`
  rows. Treat each row as part of one final-action package.

## 7. Budget process exceptions

- **Budget reconciliation:** A concurrent budget resolution instructs committees, and the resulting
  reconciliation bill is protected in the Senate (no filibuster, Byrd rule). In the House it moves
  under a rule like any other bill. In this window the main ones were the AHCA repeal attempt (2017,
  failed in the Senate), the Tax Cuts and Jobs Act (2017), the American Rescue Plan (2021), the
  Inflation Reduction Act (2022), and the 2025 reconciliation act (verify the Pub. L. number). Look
  for a passed `HCONRES` budget resolution before each.
- **Continuing resolutions and shutdowns:** If the twelve regular appropriations are not enacted by
  Oct. 1, a CR (usually an `H.R.`, sometimes an `H.J.Res.`) carries funding forward. A lapse causes a
  shutdown. Shutdowns in this window: Jan. 2018 (about 3 days), Feb. 2018 (hours), Dec. 2018–Jan.
  2019 (35 days), and Oct.–Nov. 2025, the longest on record (verify the exact dates). Omnibus and
  "minibus" packages bundle several bills together.
- **Debt limit:** Raised or suspended by ordinary bill, for example the Fiscal Responsibility Act
  (2023). The "Gephardt rule" (Rule XXVIII), which deems a debt-limit change passed when the budget
  resolution is adopted, was restored in the 116th and dropped again in the 118th (verify).
- **Pay-as-you-go:** House CUTGO (115th, 118th onward) or PAYGO (116th-117th). It creates a point
  of order, and special rules often waive it. Statutory PAYGO is a separate law.
- **Earmarks:** Banned 2011-2020. "Community Project Funding" returned for FY2022 (117th) with
  disclosure rules.

## 8. Vetoes

- **Regular veto:** The President returns the bill to the originating chamber with objections.
  The override vote is `Passage, Objections of the President To The Contrary Notwithstanding` and
  needs 2/3 of those voting in **both** chambers. The originating chamber votes first. A chamber can
  also refer the veto message to committee, which effectively kills the bill.
- **Pocket veto:** No action while Congress is adjourned. There is nothing to override, and the bill
  must be reintroduced.
- **Data:** 9 override votes, all failed. Seven were in the 118th against Biden vetoes of CRA and
  D.C. disapproval resolutions. Two were in the 119th (H.R. 504 and H.R. 131, Jan. 8, 2026). Only
  two overrides succeeded in 2015-2026, and both fall outside our cache. JASTA (S. 2040) was
  overridden in Sept. 2016, against Obama. The FY2021 NDAA was overridden in the House in Dec. 2020
  and the Senate on Jan. 1, 2021, against Trump.

## 9. Organizational exceptions

- **Speaker elections:** Held at the start of each Congress or when the chair is vacant. The vote is
  `Election of the Speaker`, and `vote_result` holds the winner's or leader's surname, not
  Passed/Failed. Rounds repeat until someone wins a majority of members voting for a named person.
  In Jan. 2023 there were 15 ballots before McCarthy won. After the chair was vacated on Oct. 3,
  2023, the House held 4 more ballots in October (3 for Jordan, then Johnson won). That adds up to
  the 19 in the 118th data. While the chair is vacant, a Speaker pro tempore named from the
  departing Speaker's list can only preside over electing a new Speaker. That is the McHenry
  precedent, and its limits are contested.
- **Motion to vacate the chair:** A privileged resolution that declares the office vacant. Who can
  offer it has changed several times (see the timeline).
- **Electoral vote count (Jan. 6 joint session):** An objection signed by a member and a senator
  sends each chamber to vote separately: `On Agreeing to the Objection`. Two such votes appear on
  Jan. 6–7, 2021. The Electoral Count Reform Act of 2022 raised the threshold to one-fifth of each
  chamber, effective for the 2025 count.
- **Proxy voting (H.Res. 965, May 2020 – end of 117th):** Members could cast votes through another
  member. Roll calls from this period show unusually high participation. Some analysts flag votes
  cast by proxy, and the Clerk lists them. The 118th ended proxy voting.
- **Vacancies:** Deaths or resignations lower the number of members, and so the majority and quorum
  needed. Narrow majorities in the 118th and 119th made this matter for close votes.
- **Unanimous consent and voice votes:** These leave no member-level record. Do not infer
  "unanimous support" from the absence of a roll call.

## Quick triage: "this vote looks weird"

| Symptom | Likely explanation |
| --- | --- |
| Many votes on one bill on one day | Amendment process in Committee of the Whole, or en bloc amendments |
| `HRES` "Providing for consideration of..." | Special rule. The bills it names are the substance |
| Bill passed with ~400 yeas and no rule | Suspension |
| Majority bill failed on suspension | Lacked 2/3. Watch for it to return under a rule |
| Rule failed | Majority-party rebellion. Look for a pulled bill or suspension workaround |
| `vote_result` is a surname | Speaker election round |
| Override vote failed | Measure is dead. Final state is vetoed |
| `HCONRES` war powers vote | Statutory expedited consideration, a policy signal that does not become law |
| Discharge motion | Majority coalition formed outside leadership control |
