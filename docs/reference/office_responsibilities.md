# Core responsibilities of each office

Legal text checked 2026-10-27 (issue #336). Each bullet is one responsibility, written in plain words, with a link to
the law that creates it. Reading level: Flesch-Kincaid grade 8.7 with the quoted legal wording included (7.4
without it). This describes the job, not how any officeholder does it. The layout is the same for every
office.

How to read it:

- **Duty** means the law says the office must do it. **Power** means the law allows it. Where the law does not make
  that split clear, the bullet says "Job".
- "Data" names the project source that covers the responsibility, or says "no data yet". Source names are the
  loaders in `docs/sources.md`. "Candidate" means a source we have researched but not loaded.
- Notes marked `[n]` are at the end of each office. They hold exceptions and conditions.
- The Missouri Constitution and the Revised Statutes of Missouri (RSMo) are quoted from revisor.mo.gov. The U.S.
  Constitution is quoted from the National Archives transcript. Quotes are short so the exact words can be checked.
  The law changes. Check the linked page for the current text.
- Words used: a **bill** is a proposed law. An **appropriation** is a law that lets the state spend money for a stated
  purpose. A **veto** is the Governor's refusal to sign a bill. **Advice and consent** means the Senate must approve
  an appointment. **Impeachment** is the formal charge that starts removal of an official from office.

## Missouri House of Representatives

- **Job.** Make state law. "The legislative power shall be vested in a senate and house of representatives" (together
  called the General Assembly). ([Mo. Const. art. III, §1][mc-iii-1]) Data: roll calls and bill actions (`mo_house`).
- **Power.** Start a bill. "Bills may originate in either house and may be amended or rejected by the other."
  ([Mo. Const. art. III, §21][mc-iii-21]) Data: bill sponsors (`mo_house`).
- **Duty.** Send every bill to a committee. "Every bill shall be referred to a committee of the house in which it is
  pending." One-third of the members can pull a bill out of committee and put it on the calendar.
  ([Mo. Const. art. III, §22][mc-iii-22]) Data: committee membership (`mo_house`); no data on pulled bills yet.
- **Duty.** Pass bills that cover one subject. "No bill shall contain more than one subject which shall be clearly
  expressed in its title." ([Mo. Const. art. III, §23][mc-iii-23]) Data: bill text (`mo_house_pdf`).
- **Duty.** Vote on the record. Each house keeps a journal and records yes and no votes when asked.
  ([Mo. Const. art. III, §26][mc-iii-26]) Data: roll calls (`mo_house`).
- **Power.** Appropriate money. "The general assembly shall have no power ... to permit the withdrawal of money from
  the treasury, except in pursuance of appropriations made by law." ([Mo. Const. art. III, §36][mc-iii-36]) Data: no
  data yet on spending (`mo_state_expenditures` is a candidate).
- **Power.** Override a veto. Two-thirds of the elected members of each house can pass a bill over the Governor's
  objections. ([Mo. Const. art. III, §32][mc-iii-32]) Data: roll calls (`mo_house`).
- **Power.** Set its own rules and judge its own members. A house "may determine the rules of its own proceedings"
  and, with two-thirds, "may expel a member". ([Mo. Const. art. III, §18][mc-iii-18]) Data: no data yet.
- **Power.** Impeach. "The house of representatives shall have the sole power of impeachment."
  ([Mo. Const. art. VII, §2][mc-vii-2]) Data: no data yet.
- **Limit.** Meet the bill deadlines. After the sixtieth legislative day, only appropriation bills can be introduced
  unless a majority of each house agrees or the Governor asks for the bill in a special message.
  ([Mo. Const. art. III, §25][mc-iii-25]) Data: bill actions (`mo_house`).

Notes:

- [1] The Speaker of the House is in the line of succession to be Governor. See the Governor notes.
   ([Mo. Const. art. IV, §11(a)][mc-iv-11a])
- [2] A bill that the Governor vetoes late in the session goes to a September session. Only bills returned on or
   after the fifth day before the last day of the session are taken up then.
   ([Mo. Const. art. III, §32][mc-iii-32])

## Missouri Senate

- **Job.** Make state law, with the House. ([Mo. Const. art. III, §1][mc-iii-1]) Data: roll calls (`mo_senate`), bill
  actions (`mo_senate_bills`).
- **Power.** Start a bill. ([Mo. Const. art. III, §21][mc-iii-21]) Data: `mo_senate_bills`.
- **Duty.** Send every bill to a committee. ([Mo. Const. art. III, §22][mc-iii-22]) Data: `mo_senate_bills`.
- **Duty.** Vote on the record. ([Mo. Const. art. III, §26][mc-iii-26]) Data: roll calls (`mo_senate`).
- **Power.** Approve or reject the Governor's choice of department heads. "The heads of all the executive departments
  shall be appointed by the governor, by and with the advice and consent of the senate."
  ([Mo. Const. art. IV, §17][mc-iv-17]) Data: no data yet.
- **Power.** Override a veto, with two-thirds of the elected senators.
  ([Mo. Const. art. III, §32][mc-iii-32]) Data: roll calls (`mo_senate`).
- **Power.** Choose its own officers and rules and expel a member with two-thirds. "Each house shall appoint its own
  officers." ([Mo. Const. art. III, §18][mc-iii-18]) Data: no data yet.
- **Power.** Choose the special commission that tries an impeached Governor or Supreme Court judge. "The governor or
  a member of the supreme court shall be tried by a special commission of seven eminent jurists to be elected by the
  senate." ([Mo. Const. art. VII, §2][mc-vii-2]) Data: no data yet.

Notes:

- [1] The Lieutenant Governor presides over the Senate. The Senate also elects a President Pro Tem. The Lieutenant
   Governor "shall cast the deciding vote on equal division in the senate."
   ([Mo. Const. art. IV, §10][mc-iv-10]) The President Pro Tem is next in line to be Governor if there is no
   Lieutenant Governor. ([Mo. Const. art. IV, §11(a)][mc-iv-11a])
- [2] Both presiding officers must sign a bill in open session before it goes to the Governor. A member can object in
   writing, and the objection goes to the Governor with the bill. ([Mo. Const. art. III, §30][mc-iii-30])

## Governor

- **Duty.** See that the laws are carried out. "The governor shall take care that the laws are distributed and
  faithfully executed." ([Mo. Const. art. IV, §2][mc-iv-2]) Data: no data yet.
- **Duty.** Act on every bill within the time limit. Within 15 days of getting a bill, the Governor returns it signed
  or with objections. After the legislature adjourns, the limit is 45 days. A bill not returned in time becomes law.
  ([Mo. Const. art. III, §31][mc-iii-31]) Data: bill actions (`mo_house`, `mo_senate_bills`).
- **Duty.** Send the legislature a budget plan within 30 days after a regular session starts.
  ([Mo. Const. art. IV, §24][mc-iv-24]) Data: no data yet.
- **Duty.** Report on the state of the government. The Governor gives the legislature this information "at the
  commencement of each session". ([Mo. Const. art. IV, §9][mc-iv-9]) Data: no data yet.
- **Power.** Veto a bill. A veto can be overridden by two-thirds of each house.
  ([Mo. Const. art. III, §32][mc-iii-32]) Data: bill actions (`mo_house`, `mo_senate_bills`).
- **Power.** Veto single items in a spending bill. The Governor "may object to one or more items or portions of items
  of appropriation of money". Money for public schools and for paying public debt cannot be cut this way.
  ([Mo. Const. art. IV, §26][mc-iv-26]) Data: bill actions; no data yet on item vetoes.
- **Power.** Slow or cut spending when revenue falls short. The Governor "may control the rate at which any
  appropriation is expended" and may cut spending when "actual revenues are less than the revenue estimates".
  ([Mo. Const. art. IV, §27][mc-iv-27]) Data: no data yet (`mo_state_expenditures` is a candidate).
- **Power.** Call a special session. "On extraordinary occasions he may convene the general assembly by
  proclamation." ([Mo. Const. art. IV, §9][mc-iv-9]) Data: bill actions in special sessions (`mo_senate_bills`).
- **Power.** Appoint. The Governor fills vacancies in public offices, and appoints department heads with Senate
  approval. ([Mo. Const. art. IV, §4][mc-iv-4], [art. IV, §17][mc-iv-17]) Data: no data yet.
- **Power.** Appoint judges to open seats on the courts that use the Missouri nonpartisan court plan, from a list of
  three names. ([Mo. Const. art. V, §25(a)][mc-v-25a]) Data: judge careers (`bluebook`, `courtlistener_bulk`).
- **Power.** Grant pardons, commutations (shorter sentences) and reprieves (delays) "after conviction, for all
  offenses except treason and cases of impeachment". ([Mo. Const. art. IV, §7][mc-iv-7]) Data: no data yet.
- **Power.** Command the state militia (the National Guard). The Governor "shall be the commander in chief of the
  militia, except when it is called into the service of the United States."
  ([Mo. Const. art. IV, §6][mc-iv-6]) Data: no data yet.

Notes:

- [1] If the Governor dies, resigns or is removed, the Lieutenant Governor becomes Governor for the rest of the term.
   If the Governor is absent or cannot serve, the Lieutenant Governor takes over the powers until the problem ends.
   ([Mo. Const. art. IV, §11(a)][mc-iv-11a])
- [2] A Governor can be impeached by the House and tried by a special commission picked by the Senate.
   ([Mo. Const. art. VII, §1][mc-vii-1], [art. VII, §2][mc-vii-2])
- [3] Terms are four years. No one may be elected Governor more than twice. ([Mo. Const. art. IV, §17][mc-iv-17])

## Lieutenant Governor

- **Duty.** Preside over the Senate. The Lieutenant Governor is "ex officio president of the senate" (that is, holds
  the post because of the office). ([Mo. Const. art. IV, §10][mc-iv-10]) Data: no data yet.
- **Power.** Break ties. The Lieutenant Governor "shall cast the deciding vote on equal division in the senate and on
  joint vote of both houses." ([Mo. Const. art. IV, §10][mc-iv-10]) Data: roll calls (`mo_senate`) where a tie
  occurred.
- **Power.** Debate in the Senate when it sits as a committee of the whole. ([Mo. Const. art. IV, §10][mc-iv-10])
  Data: no data yet.
- **Duty.** Take over as Governor when the law says so (see note 1).
  ([Mo. Const. art. IV, §11(a)][mc-iv-11a]) Data: no data yet.

Notes:

- [1] The Lieutenant Governor becomes Governor for the rest of the term on the Governor's death, conviction,
   impeachment or resignation. The Lieutenant Governor only acts as Governor if the Governor is absent or unable to
   serve. ([Mo. Const. art. IV, §11(a)][mc-iv-11a])
- [2] The Lieutenant Governor must follow the Senate's own rules while presiding.
   (Court ruling noted on [Mo. Const. art. IV, §10][mc-iv-10]: State v. Cason, 507 S.W.2d 405 (Mo. 1974).)

## Secretary of State

- **Duty.** Keep the Great Seal of Missouri and use it on the Governor's official acts. The Secretary of State "shall
  be custodian of the seal of the state". ([Mo. Const. art. IV, §14][mc-iv-14]) Data: no data yet.
- **Duty.** Keep a register of the Governor's official acts. ([Mo. Const. art. IV, §14][mc-iv-14]) Data: no data yet.
- **Duty.** Keep state records and handle the work the law gives the office for elections and corporations. The
  Secretary of State "shall be custodian of such records, and documents ... in relation to elections and
  corporations, as provided by law". ([Mo. Const. art. IV, §14][mc-iv-14]) Data: election returns (`mo_sos_elections`
  is a candidate); business filings (`mo_sos_business` is a candidate).
- **Duty.** Collect statewide election returns and appoint two judges who join the Secretary to form the board that
  canvasses (officially counts) them. ([Mo. Const. art. IV, §18][mc-iv-18]) Data: no data yet.
- **Duty.** Receive the rules of state agencies for filing. Most rules "shall take effect not less than ten days after
  the filing thereof in the office of the secretary of state". ([Mo. Const. art. IV, §16][mc-iv-16]) Data: no data
  yet (`mo_sos_rules` is a candidate).
- **Duty.** Receive bills the Governor returns after the legislature adjourns. When the legislature has adjourned,
  the Governor returns a bill "to the office of the secretary of state". ([Mo. Const. art. III, §31][mc-iii-31]) Data:
  no data yet.

Notes:

- [1] The Constitution limits the office: "no duty shall be imposed on him by law which is not related to his duties
   as prescribed in this constitution." ([Mo. Const. art. IV, §14][mc-iv-14])
- [2] The Secretary of State is in the line of succession to be Governor.
   ([Mo. Const. art. IV, §11(a)][mc-iv-11a])

## State Auditor

- **Duty.** Set up accounting systems for all state officials. The Auditor "shall establish appropriate systems of
  accounting for all public officials of the state". ([Mo. Const. art. IV, §13][mc-iv-13]) Data: no data yet.
- **Duty.** Check the accounts of all state agencies after the fact (a "post-audit") and audit the treasury at least
  once a year. ([Mo. Const. art. IV, §13][mc-iv-13]) Data: audit reports (`mo_auditor`).
- **Duty.** Make the other audits and investigations the law requires, and send an annual report to the Governor and
  the legislature. ([Mo. Const. art. IV, §13][mc-iv-13]) Data: audit reports (`mo_auditor`).
- **Duty.** Set up accounting systems for local governments, watch their budgeting and audit their accounts "as
  provided by law". ([Mo. Const. art. IV, §13][mc-iv-13]) Data: audit reports of counties, cities and schools
  (`mo_auditor`).
- **Job.** Approve, with the Governor, the banks where the Treasurer deposits state money.
  ([Mo. Const. art. IV, §15][mc-iv-15]) Data: no data yet.

Notes:

- [1] The Constitution limits the office: "No duty shall be imposed on him by law which is not related to the
   supervising and auditing of the receipt and expenditure of public funds." ([Mo. Const. art. IV, §13][mc-iv-13])
- [2] The Auditor is in the line of succession to be Governor. ([Mo. Const. art. IV, §11(a)][mc-iv-11a])
- [3] The Missouri Supreme Court has held that the Auditor lacked standing to challenge the Governor's power to
   withhold funds. (Noted on [Mo. Const. art. IV, §13][mc-iv-13]: Schweich v. Nixon, 408 S.W.3d 769 (Mo. 2013).)

## State Treasurer

- **Duty.** Hold all state money and money from the federal government. The Treasurer "shall be custodian of all
  state funds and funds received from the United States government". ([Mo. Const. art. IV, §15][mc-iv-15]) Data: no
  data yet (`mo_state_expenditures` is a candidate).
- **Duty.** Deposit state money in banks the Treasurer picks and the Governor and Auditor approve, and pay it out "as
  provided by law". ([Mo. Const. art. IV, §15][mc-iv-15]) Data: no data yet.
- **Duty.** Invest money not needed right away, in interest-bearing bank deposits or U.S. government obligations.
  ([Mo. Const. art. IV, §15][mc-iv-15]) Data: no data yet.

Notes:

- [1] Money that is not state money, called "nonstate funds" in the Constitution, is held and invested by the
   Department of Revenue, not the Treasurer. ([Mo. Const. art. IV, §15][mc-iv-15])
- [2] No one may be elected Treasurer more than twice. ([Mo. Const. art. IV, §17][mc-iv-17])
- [3] The Treasurer is in the line of succession to be Governor. ([Mo. Const. art. IV, §11(a)][mc-iv-11a])

## Attorney General

- **Duty.** Represent the state in the Court of Appeals and Supreme Court. The Attorney General "shall appear on
  behalf of the state in the court of appeals and in the supreme court". ([RSMo 27.050][rsmo-27-050]) Data: court
  dockets (`courtlistener_case_bulk`).
- **Duty.** File and defend civil cases to protect the state's rights. The Attorney General "shall institute, in the
  name and on the behalf of the state, all civil suits and other proceedings at law or in equity requisite or
  necessary to protect the rights and interests of the state". ([RSMo 27.060][rsmo-27-060]) Data: court dockets
  (`courtlistener_case_bulk`).
- **Duty.** Give written legal opinions when asked by the legislature, the Governor, statewide officials, department
  heads, and circuit or prosecuting attorneys. ([RSMo 27.040][rsmo-27-040]) Data: no data yet.
- **Duty.** Help a prosecuting or circuit attorney in trial courts and grand jury work when the Governor directs.
  ([RSMo 27.030][rsmo-27-030]) Data: no data yet.

Notes:

- [1] The office is created in the Constitution but its duties come from statutes, so this list is from RSMo chapter
   27 and is not complete. ([Mo. Const. art. IV, §12][mc-iv-12]) Open item: other chapter 27 duties, such as consumer
   protection, are not yet listed (see the follow-up issue in the pull request).
- [2] The Attorney General is last in the line of succession to be Governor.
   ([Mo. Const. art. IV, §11(a)][mc-iv-11a])
- [3] Attorney General opinions carry no more weight than those of any other competent lawyer. (Noted on
   [RSMo 27.040][rsmo-27-040]: Gershman Investment Corp. v. Danforth, 517 S.W.2d 33 (Mo. 1974).)

## Missouri judges (Supreme Court, Court of Appeals, circuit courts)

- **Job.** Hold the state's judicial power. "The judicial power of the state shall be vested in a supreme court, a
  court of appeals consisting of districts as prescribed by law, and circuit courts."
  ([Mo. Const. art. V, §1][mc-v-1]) Data: dockets and opinions (`courtlistener_case_bulk`).
- **Duty (Supreme Court).** Hear certain cases that only it can hear on appeal, such as cases about the validity of a
  federal treaty or statute or a provision of the state constitution, state revenue laws, title to a state office,
  and death sentences. ([Mo. Const. art. V, §3][mc-v-3]) Data: `courtlistener_case_bulk`.
- **Duty (Supreme Court).** Be the highest court in the state. "Its decisions shall be controlling in all other
  courts." ([Mo. Const. art. V, §2][mc-v-2]) Data: `courtlistener_case_bulk`.
- **Duty (Court of Appeals).** Hear appeals in all other cases. The court "shall have general appellate jurisdiction
  in all cases except those within the exclusive jurisdiction of the supreme court."
  ([Mo. Const. art. V, §3][mc-v-3]) Data: `courtlistener_case_bulk`.
- **Duty (circuit courts).** Hear cases first. "The circuit courts shall have original jurisdiction over all cases and
  matters, civil and criminal." ([Mo. Const. art. V, §14][mc-v-14]) Data: `courtlistener_case_bulk` covers only
  part of this.
- **Duty (associate circuit judges).** Hear and decide the cases the law gives them, including civil and criminal
  cases, and probate matters. ([Mo. Const. art. V, §17][mc-v-17]) Data: no data yet.
- **Power (Supreme Court).** Write the rules for how courts work. The court "may establish rules relating to
  practice, procedure and pleading for all courts and administrative tribunals". The legislature can annul or amend a
  rule by a law limited to that purpose. ([Mo. Const. art. V, §5][mc-v-5]) Data: Court Operating Rule 2 is on file in
  `docs/reference/court_operating_rule_2.md`; no rule-change data yet.

Notes:

- [1] Terms: 12 years for Supreme Court and Court of Appeals judges, 6 years for circuit judges, 4 years for
   associate circuit judges. ([Mo. Const. art. V, §19][mc-v-19]) Data: `bluebook`, `mo_sos_elections` (candidate) for
   retention votes.
- [2] Seats on the Supreme Court, the Court of Appeals, and the circuit courts of St. Louis city and Jackson County
   are filled by Governor appointment from a three-name list from a nonpartisan commission.
   ([Mo. Const. art. V, §25(a)][mc-v-25a]) Other circuits elect their judges. ([Mo. Const. art. V, §16][mc-v-16])
- [3] Each circuit's judges pick a presiding judge, who has "general administrative authority over the court".
   ([Mo. Const. art. V, §15][mc-v-15])
- [4] Judges can be impeached for "crimes, misconduct, habitual drunkenness, willful neglect of duty, corruption in
   office, incompetency, or any offense involving moral turpitude or oppression in office."
   ([Mo. Const. art. VII, §1][mc-vii-1]) An impeached Supreme Court judge is tried by a special commission of seven
   jurists chosen by the Senate; other impeached judges are tried before the Supreme Court.
   ([Mo. Const. art. VII, §2][mc-vii-2])

## U.S. House of Representatives

- **Job.** Make federal law, with the Senate. "All legislative Powers herein granted shall be vested in a Congress of
  the United States". ([U.S. Const. art. I, §1][us-const]) Data: roll calls (`voteview`), bills
  (`govinfo_billstatus`).
- **Power.** Start all bills that raise taxes. "All Bills for raising Revenue shall originate in the House of
  Representatives". ([U.S. Const. art. I, §7][us-const]) Data: `govinfo_billstatus`.
- **Power.** Tax and borrow. Congress has the power "To lay and collect Taxes, Duties, Imposts and Excises" and "To
  borrow Money on the credit of the United States". ([U.S. Const. art. I, §8][us-const]) Data:
  `govinfo_billstatus`.
- **Power.** Appropriate money. "No Money shall be drawn from the Treasury, but in Consequence of Appropriations made
  by Law". ([U.S. Const. art. I, §9][us-const]) Data: `govinfo_billstatus`; no spending data yet.
- **Power.** Declare war, raise armies and run a navy. ([U.S. Const. art. I, §8][us-const]) Data: roll calls
  (`voteview`).
- **Power.** Impeach. "The House of Representatives ... shall have the sole Power of Impeachment."
  ([U.S. Const. art. I, §2][us-const]) Data: roll calls (`voteview`).
- **Power.** Set its own rules, judge its own members' elections and qualifications, and choose its Speaker and
  officers. ([U.S. Const. art. I, §2 and §5][us-const]) Data: roll calls (`voteview`).

Notes:

- [1] Members are "chosen every second Year by the People of the several States." ([U.S. Const. art. I, §2][us-const])
- [2] A bill the President vetoes can still become law if two-thirds of each chamber vote to pass it again.
   ([U.S. Const. art. I, §7][us-const])

## U.S. Senate

- **Job.** Make federal law, with the House. ([U.S. Const. art. I, §1][us-const]) Data: roll calls (`voteview`),
  bills (`govinfo_billstatus`).
- **Power.** Approve or reject the President's picks. The President "shall nominate, and by and with the Advice and
  Consent of the Senate, shall appoint Ambassadors, other public Ministers and Consuls, Judges of the supreme Court,
  and all other Officers of the United States". ([U.S. Const. art. II, §2][us-const]) Data: roll calls
  (`voteview`).
- **Power.** Approve treaties. The President can make treaties "by and with the Advice and Consent of the Senate ...
  provided two thirds of the Senators present concur". ([U.S. Const. art. II, §2][us-const]) Data: roll calls
  (`voteview`).
- **Power.** Try impeachments. "The Senate shall have the sole Power to try all Impeachments." Conviction needs
  two-thirds of the members present. ([U.S. Const. art. I, §3][us-const]) Data: roll calls (`voteview`).
- **Power.** Tax, borrow, appropriate, declare war (shared with the House). ([U.S. Const. art. I, §8 and §9][us-const])
  Data: roll calls (`voteview`).
- **Power.** Amend or agree to tax bills from the House. "the Senate may propose or concur with Amendments as on other
  Bills". ([U.S. Const. art. I, §7][us-const]) Data: `govinfo_billstatus`.

Notes:

- [1] Each state has two Senators with six-year terms. ([U.S. Const. art. I, §3][us-const]) The Article's wording
   on how Senators are chosen has been changed by a later amendment, which this page does not quote.
- [2] The Vice President presides over the Senate but votes only to break a tie. The Senate also picks a President
   pro tempore for when the Vice President is absent. When a President is tried, the Chief Justice presides.
   ([U.S. Const. art. I, §3][us-const])

## Federal judges

- **Job.** Hold the federal judicial power. "The judicial Power of the United States, shall be vested in one supreme
  Court, and in such inferior Courts as the Congress may from time to time ordain and establish."
  ([U.S. Const. art. III, §1][us-const]) Data: judge careers (`fjc_judges`, `courtlistener_bulk`), dockets
  (`courtlistener_case_bulk`).
- **Duty.** Decide the cases the Constitution assigns to federal courts. The power "shall extend to all Cases, in Law
  and Equity, arising under this Constitution, the Laws of the United States, and Treaties". It also covers
  cases involving ambassadors, maritime law, the United States as a party, and disputes between states.
  ([U.S. Const. art. III, §2][us-const]) Data: dockets (`courtlistener_case_bulk`, `courtlistener_cases`).
- **Job.** Serve for life, if they keep up good behavior. Judges "shall hold their Offices during good Behaviour".
  Their pay cannot be cut while they hold office. ([U.S. Const. art. III, §1][us-const]) Data: `fjc_judges`.

Notes:

- [1] The President appoints federal judges with the Senate's advice and consent.
   ([U.S. Const. art. II, §2][us-const])
- [2] Federal judges can be impeached by the House and tried by the Senate.
   ([U.S. Const. art. I, §2 and §3][us-const])

## Offices not covered yet

Sheriffs, prosecutors and other local officers (#178), county and city officials, and the State Auditor's local
audits beyond the Constitution's wording are not in this first version. Statewide boards and commissions an office sits
on by law (for example, the Governor and Auditor approving state bank deposits, noted above) are listed only where the
Constitution says so. Statutes that add duties are listed only for the Attorney General.

## Links

[mc-iii-1]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++1&constit=y
[mc-iii-18]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++18&constit=y
[mc-iii-21]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++21&constit=y
[mc-iii-22]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++22&constit=y
[mc-iii-23]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++23&constit=y
[mc-iii-25]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++25&constit=y
[mc-iii-26]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++26&constit=y
[mc-iii-30]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++30&constit=y
[mc-iii-31]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++31&constit=y
[mc-iii-32]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++32&constit=y
[mc-iii-36]: https://revisor.mo.gov/main/OneSection.aspx?section=III++++36&constit=y
[mc-iv-2]: https://revisor.mo.gov/main/OneSection.aspx?section=IV+++++2&constit=y
[mc-iv-4]: https://revisor.mo.gov/main/OneSection.aspx?section=IV+++++4&constit=y
[mc-iv-6]: https://revisor.mo.gov/main/OneSection.aspx?section=IV+++++6&constit=y
[mc-iv-7]: https://revisor.mo.gov/main/OneSection.aspx?section=IV+++++7&constit=y
[mc-iv-9]: https://revisor.mo.gov/main/OneSection.aspx?section=IV+++++9&constit=y
[mc-iv-10]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++10&constit=y
[mc-iv-11a]: https://revisor.mo.gov/main/OneSection.aspx?section=IV+++11(a)&constit=y
[mc-iv-12]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++12&constit=y
[mc-iv-13]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++13&constit=y
[mc-iv-14]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++14&constit=y
[mc-iv-15]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++15&constit=y
[mc-iv-16]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++16&constit=y
[mc-iv-17]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++17&constit=y
[mc-iv-18]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++18&constit=y
[mc-iv-24]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++24&constit=y
[mc-iv-26]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++26&constit=y
[mc-iv-27]: https://revisor.mo.gov/main/OneSection.aspx?section=IV++++27&constit=y
[mc-v-1]: https://revisor.mo.gov/main/OneSection.aspx?section=V+++++1&constit=y
[mc-v-2]: https://revisor.mo.gov/main/OneSection.aspx?section=V+++++2&constit=y
[mc-v-3]: https://revisor.mo.gov/main/OneSection.aspx?section=V+++++3&constit=y
[mc-v-5]: https://revisor.mo.gov/main/OneSection.aspx?section=V+++++5&constit=y
[mc-v-14]: https://revisor.mo.gov/main/OneSection.aspx?section=V++++14&constit=y
[mc-v-15]: https://revisor.mo.gov/main/OneSection.aspx?section=V++++15&constit=y
[mc-v-16]: https://revisor.mo.gov/main/OneSection.aspx?section=V++++16&constit=y
[mc-v-17]: https://revisor.mo.gov/main/OneSection.aspx?section=V++++17&constit=y
[mc-v-19]: https://revisor.mo.gov/main/OneSection.aspx?section=V++++19&constit=y
[mc-v-25a]: https://revisor.mo.gov/main/OneSection.aspx?section=V+++25(a)&constit=y
[mc-vii-1]: https://revisor.mo.gov/main/OneSection.aspx?section=VII+++1&constit=y
[mc-vii-2]: https://revisor.mo.gov/main/OneSection.aspx?section=VII+++2&constit=y
[rsmo-27-030]: https://revisor.mo.gov/main/OneSection.aspx?section=27.030
[rsmo-27-040]: https://revisor.mo.gov/main/OneSection.aspx?section=27.040
[rsmo-27-050]: https://revisor.mo.gov/main/OneSection.aspx?section=27.050
[rsmo-27-060]: https://revisor.mo.gov/main/OneSection.aspx?section=27.060
[us-const]: https://www.archives.gov/founding-docs/constitution-transcript
