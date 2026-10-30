{% docs official_id %}
Stable key for a current official, shared by every mart. Its prefix tells you where the identity comes from:

| Form | Who |
|---|---|
| `ocd-person/<uuid>` | anyone Open States knows (legislators, statewide officers, mayors) |
| `bioguide:<id>` | members of Congress without an Open States id |
| `fjc:<nid>` | federal judges (Federal Judicial Center node id) |
| `mojudge:<key>` | Missouri state judges (Official Manual) |
| `mohouse:<id>` | MO House members missing from Open States |
| `statewide:<office>:<name key>` | statewide executives from the `statewide_officials` seed with no Open States id; the name keeps the id with the person when the office changes hands |

Join any fact to `dim_official` on this column.
{% enddocs %}

{% docs office %}
Machine code for the office currently held: `governor`, `lt_governor`, `secretary_of_state`, `state_auditor`,
`state_treasurer`, `attorney_general`, `state_senate`, `state_house`, `us_senate`, `us_house`, `mayor`,
`mo_supreme_court`, `mo_court_of_appeals`, `mo_circuit_judge`, `mo_associate_circuit_judge`,
`us_district_court`, `us_court_of_appeals`. `office_title` is the human-readable form.
{% enddocs %}

{% docs level %}
Government level of the current office: `state`, `federal` or `local` (mayors).
{% enddocs %}

{% docs source_url %}
Link to the record at its source (MEC, FEC, Voteview, CourtListener, a disclosure PDF...), for a reader to
verify the row. Null where the value is computed here (e.g. party unity).
{% enddocs %}

{% docs match_confidence %}
How the row was tied to the official, for sources that don't carry our ids:

| Value | Meaning |
|---|---|
| `exact id` | joined on a shared identifier (FEC candidate id, bioguide id) |
| `exact (MEC crosswalk)` | MEC's own candidate<->committee export names this committee |
| `high` | name match on first and last name |
| `medium` | surname match with a weaker first-name signal (first three letters, or a surname-first committee name with no other official sharing the surname) |

Treat `medium` rows with care before publishing them as fact.
{% enddocs %}

{% docs vote_cast %}
How the official voted: `yea`, `nay`, `present`, `absent`, `absent with leave` (MO Senate), `recused`
(MO Senate "Excused from voting": a Senate Rule 91 recusal by a member present on the floor, not an absence),
`not voting` (Congress; Voteview code 9, which does not say whether the absence was excused). State votes are
read from roll-call PDFs and journals; federal from Voteview cast codes.
{% enddocs %}

{% docs coverage_status %}
Why this category has, or lacks, records for this official:

| Value | Meaning |
|---|---|
| `available` | records found |
| `none found` | a source covers this official, nothing matched (a parenthetical says which gap) |
| `none recorded (...)` | no public list exists, so we hold only entries added by hand (voluntary disclosures); not a search that came up empty |
| `not applicable` | the category doesn't apply to this office |
| `not public (...)` | required by law but not published online; the parenthetical says whom to ask under the Sunshine Law |
{% enddocs %}
