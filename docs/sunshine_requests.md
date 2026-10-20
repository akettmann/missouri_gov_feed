# Sunshine Law requests

Some records we want are public but not online. They have to be requested from the body that holds them.
This page covers what a request needs and has a template letter for each request we plan to make.
Records that arrive go in through a seed or a local-folder loader (see TODO.md).

## What a request needs

Missouri's Sunshine Law is RSMo Chapter 610. Researched October 2026; check the statute text on
revisor.mo.gov before relying on a detail.

- **Who it goes to.** Every public governmental body appoints a custodian of records. The custodian's
  identity and location must be given on request (§ 610.023.1). Address the request to the custodian.
- **Format.** The law requires no particular form or wording. A written request (email or letter) is still
  best, because it sets the date the response clock starts. Citing Chapter 610 removes any doubt about what
  the message is. The requester doesn't have to say why they want the records.
- **Deadline.** The body must act "as soon as possible, but in no event later than the end of the third
  business day following the date the request is received" (§ 610.023.3). If it needs longer, it must
  explain why and give the earliest date the records will be available. A body can take longer for
  reasonable cause, and in practice large requests often do.
- **Denials.** On request, the custodian must give a written statement citing the specific law that closes
  the record, by the end of the third business day after it's asked for (§ 610.023.4). If only part of a
  record is closed, the body must separate the closed part and release the rest (§ 610.024).
- **Fees** (§ 610.026):
  - Paper copies cost at most 10¢ a page, up to 9" × 14". Duplicating time is charged at no more than the
    average clerical hourly rate.
  - Research time can be charged at actual cost. Attorney review time is not research time
    (*Gross v. Parson*, 624 S.W.3d 877).
  - Electronic records: the cost of copies, the medium, and staff time at the average staff hourly rate.
  - The requester can ask for a cost estimate before copies are made. The body can require payment in
    advance. A request is treated as withdrawn if fees aren't paid within 90 days (150 days if over $1,000).
  - Fees can be waived or reduced when the release is in the public interest: it will "contribute
    significantly to public understanding" of the body's operations and is not primarily commercial.
- **Courts are different.** Courts fall under Chapter 610 only "when operating in an administrative
  capacity" (§ 610.010(4)). Court records are governed by Court Operating Rule 2 (COR 2, effective July 1,
  2023):
  - Administrative records are generally open (COR 2.06), and requests for them must be in writing
    (COR 2.08).
  - The requester doesn't have to give a purpose. The custodian responds "as promptly as practical" and may
    charge reasonable fees.
  - Denials are in writing if asked for, and can be appealed to the State Judicial Records Committee
    (COR 2.09).

### Personal financial disclosures (PFDs)

- **Who files where.** Legislators, statewide officials and their designated staff, candidates, and
  judicial candidates who are not sitting judges file with the Missouri Ethics Commission (MEC). Supreme
  Court, appellate, circuit and associate circuit judges file with the Clerk of the Missouri Supreme Court
  (§§ 105.483, 105.489; MEC Ethics Guide 2026).
- **They are public, but not online.** MEC: "State law requires a request to receive copies of PFDs filed
  with the Commission." MEC provides copies "upon written request" and charges a copying fee for most
  requests (MEC PFD FAQ, citing § 105.491). Judges' statements are "available for public inspection unless
  otherwise provided by supreme court rule" (§ 105.489). We found no such rule and no published request
  procedure, so the letter asks in writing under both the statute and COR 2.
- **Retention.** Filing officers keep statements for at least five years (§ 105.491.1(3)). Ask for the last
  five filing years; older years may already be destroyed.
- **Requests are logged publicly.** Every filing officer keeps a public log of who inspected or copied each
  statement (§ 105.491.2). Our name and contact information will be visible to the filers and to anyone
  else who asks.
- **Filing calendar.** Annual filers file by May 1 for the previous calendar year. Requests sent after
  mid-May get the newest year.
- **Precedent.** American Oversight got the Attorney General's PFDs from MEC with an emailed Sunshine
  request in June 2021 (their request MO-MEC-21-0839).

## Building the request lists

PFD requests name the filers. Generate the lists from `dim_official` rather than typing them, and attach
them to the letter as a CSV. `dim_official` holds current officeholders only (October 2026: 188 legislators
and 7 statewide officers for MEC, 346 judges for the Clerk). People who left office during the requested
years have to be added by hand.

```sql
-- MEC: legislators and statewide officers
select full_name, office_title, district, party
from marts.dim_official
where level = 'state'
    and office not in ('mo_supreme_court', 'mo_court_of_appeals', 'mo_circuit_judge', 'mo_associate_circuit_judge')
order by office, district;

-- Clerk of the Supreme Court: state judges
select full_name, office_title, district
from marts.dim_official
where office in ('mo_supreme_court', 'mo_court_of_appeals', 'mo_circuit_judge', 'mo_associate_circuit_judge')
order by office, district, full_name;
```

## Template: Missouri Ethics Commission (officials' and candidates' PFDs)

Send by email to helpdesk@mec.mo.gov, with the mailing address in the letter. MEC's Sunshine policy sends
postal requests to P.O. Box 1254. American Oversight used the helpdesk address; call (573) 751-2020 to
confirm it is still the intake address.

```text
{{DATE}}

Executive Director, Custodian of Records
Missouri Ethics Commission
P.O. Box 1254
Jefferson City, MO 65102
helpdesk@mec.mo.gov

Re: Sunshine Law request - personal financial disclosure statements

Dear Custodian of Records:

This is a request for records under the Missouri Sunshine Law, Chapter 610, RSMo.

Records requested

Copies of every Personal Financial Disclosure statement (financial interest statement under
sections 105.483 to 105.492, RSMo), including any amendments, filed with the Commission by or on behalf
of each person listed in the attached list, for calendar years {{FIRST_YEAR}} through {{LAST_YEAR}}.

The attached list ({{N}} people) names {{DESCRIPTION, e.g. "every member of the Missouri General
Assembly serving in 2021-2026 and each statewide officeholder"}}.

Format

Please provide the records electronically, as PDF files sent to the email address below or through a
download link. Section 610.023.3 requires a requested format to be used when it is available. Electronic
copies should keep copying costs to a minimum.

Fees

I ask that all fees be waived under section 610.026.1(1). The records will be used for
{{PROJECT_DESCRIPTION, e.g. "a free, non-commercial public website that shows Missouri voters the
financial interests, campaign donors and voting records of their elected officials side by side"}}.
Publishing them will contribute significantly to public understanding of the operations and activities
of government, and the request is not primarily in my commercial interest.

If fees are not waived, please send me an estimate before any search or copying if the total will
exceed ${{FEE_LIMIT}}.

Other

If any part of a responsive record is closed, please separate the closed part, release the rest
(section 610.024), and give me a written statement of the specific law under which the rest is closed
(section 610.023.4).

If it will help to release records in batches as they are located, I'm happy to receive them that way.

Thank you. I can be reached at the email address or phone number below with any questions about
the scope of this request.

{{NAME}}
{{MAILING_ADDRESS}}
{{EMAIL}}
{{PHONE}}
```

## Template: Clerk of the Missouri Supreme Court (judges' PFDs)

The Clerk is the filing officer for judges (§ 105.489). Send by mail, or fax (573) 751-7514. We found no
records-request email; ask the Clerk's office, (573) 751-4144, whether email is accepted. The letter cites
both § 105.489 and COR 2, because Chapter 610 reaches courts only in their administrative capacity.

```text
{{DATE}}

Clerk of the Supreme Court of Missouri, Custodian of Records
Supreme Court Building
207 West High Street
P.O. Box 150
Jefferson City, MO 65102

Re: Request for judges' financial interest statements (section 105.489, RSMo; Court Operating Rule 2)

Dear Clerk:

Under section 105.489, RSMo, the Clerk of the Supreme Court is the filing officer for the financial
interest statements of judges, and those statements are available for public inspection. I request
copies of these records under section 105.489, Court Operating Rule 2 (administrative records,
COR 2.06 and 2.08), and, to the extent it applies, the Sunshine Law, Chapter 610, RSMo.

Records requested

Copies of every financial interest statement (personal financial disclosure), including any
amendments, filed with the Clerk by or on behalf of each judge listed in the attached list, for
calendar years {{FIRST_YEAR}} through {{LAST_YEAR}}.

The attached list ({{N}} judges) covers {{DESCRIPTION, e.g. "every judge of the Supreme Court, the
Court of Appeals, and the circuit and associate circuit courts serving in 2021-2026"}}.

If your office keeps an index or log of these filings (filer, court, date filed), I also request a copy
of that index for the same years.

Format

Please provide the records electronically, as PDF files sent to the email address below or through a
download link, if available.

Fees

I ask that fees be waived or reduced. The records will be used for {{PROJECT_DESCRIPTION}}. The request
is not for commercial purposes. If there will be a charge, please send me an estimate before copying if
the total will exceed ${{FEE_LIMIT}}.

If any record or part of a record is withheld, please release the rest and tell me in writing which
rule or statute it is withheld under (COR 2.08), so that I can ask the State Judicial Records Committee
to review the decision if needed (COR 2.09).

Thank you for your help.

{{NAME}}
{{MAILING_ADDRESS}}
{{EMAIL}}
{{PHONE}}
```

## Template: Secretary of State (business entity extract)

For the "companies in an official's jurisdiction" TODO item. The Secretary of State's business entity
search has no bulk export. The only bulk product we found is UCC data, sold by written agreement
(15 CSR 30-90.075). The entity records are public records, so ask for an extract. Email
CustodianOfRecords@sos.mo.gov (used by 2024 requests; info@sos.mo.gov in earlier ones), or mail 600 West
Main Street, Jefferson City, MO 65101.

```text
{{DATE}}

Custodian of Records
Office of the Missouri Secretary of State
600 West Main Street
Jefferson City, MO 65101
CustodianOfRecords@sos.mo.gov

Re: Sunshine Law request - business entity registry extract

Dear Custodian of Records:

This is a request for records under the Missouri Sunshine Law, Chapter 610, RSMo.

Records requested

An electronic extract of the business entity records maintained by the Corporations Division, as of
the date of the search, with these fields for each entity (active and inactive): charter number,
entity name, entity type, status, date formed, date of status change, state of formation, principal
office address, registered agent name and address, and any NAICS or business-purpose code recorded.

Format

A delimited text file (CSV or similar) or a database export, sent by email or download link.
Section 610.023.3 requires a requested format to be used when it is available, and section
610.026.1(2) limits charges for computer records to copies, the medium and staff time; programming
beyond the customary level may be charged at actual cost. If producing the extract would need custom
programming, please tell me the estimated cost first.

If your office already offers this data as a bulk product or subscription, please send me its terms
and price instead.

Fees

I ask that fees be waived under section 610.026.1(1). The data will be used for
{{PROJECT_DESCRIPTION}}, and the request is not primarily commercial. If fees are not waived, please
send an estimate first if the total will exceed ${{FEE_LIMIT}}.

If any field is closed, please release the rest and cite the law closing that field
(sections 610.023.4 and 610.024).

{{NAME}}
{{MAILING_ADDRESS}}
{{EMAIL}}
{{PHONE}}
```

## Tracking

Log each request when it goes out: body, date sent, the date the three-business-day deadline falls on, and
each response. If a body misses the deadline without explaining why, a written follow-up citing
§ 610.023.3 is the next step. The Attorney General's office mediates Sunshine complaints about state
bodies.

## Sources

Copies of the full texts, retrieved October 19, 2026, are in `docs/reference/`:
[RSMo Chapter 610](reference/rsmo_chapter_610_sunshine_law.md),
[RSMo 105.483–105.492](reference/rsmo_105_483_to_105_492_financial_interest.md) and
[Court Operating Rule 2](reference/court_operating_rule_2.md). The online versions below are authoritative.

- RSMo [§ 610.010](https://revisor.mo.gov/main/OneSection.aspx?section=610.010),
  [§ 610.023](https://revisor.mo.gov/main/OneSection.aspx?section=610.023),
  [§ 610.026](https://revisor.mo.gov/main/OneSection.aspx?section=610.026),
  [§ 105.489](https://revisor.mo.gov/main/OneSection.aspx?section=105.489),
  [§ 105.491](https://revisor.mo.gov/main/OneSection.aspx?section=105.491)
- [MEC Sunshine Law Policy](https://www.mec.mo.gov/WebDocs/PDF/Misc/MECSunshineLawPolicy.pdf) (readopted
  2018), [MEC Ethics Guide 2026](https://mec.mo.gov/WebDocs/PDF/Press/EthicsGuide2026.pdf),
  [MEC PFD FAQ](https://www.mec.mo.gov/WebDocs/PDF/PFD/PFDFAQs.pdf)
- [Court Operating Rule 2](https://www.courts.mo.gov/courts/ClerkHandbooksP2RulesOnly.nsf/E2AA3309EF5C449186256BE20060C329/DC2E80286AFA4AD286256CA60051DEE2)
- [Attorney General sample records request](https://ago.mo.gov/get-help/programs-services-from-a-z/sunshine-law/sample-language-forms/records-request-form/)
- [American Oversight, MO-MEC-21-0839](https://americanoversight.org/foia/mo-mec-21-0839)
