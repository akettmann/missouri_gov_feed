# Interest keywords: how donor PACs are classified

`int_interests__industry_money` puts a donor organization or lobbyist principal in an industry when its name
contains a whole-word keyword from the `interest_keywords` seed. Words that name the industry outright
("hospital", "bankers") and well-known companies need no research. A PAC acronym is added only after its
sponsor is confirmed from one of the sources below. This page records that evidence, so the next person can
check it instead of repeating the search.

## Sources

| Source | What it gives | How to use it |
| --- | --- | --- |
| MEC committee page, `https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=<id>` | Committee name, type, address, treasurer (with phone), officers, **connected organizations** | Public, no login. Find the MECID in `staging.stg_mec__contributions_made` (`committee_name`, `mec_committee_id`). Most PACs leave "Connected Organizations" as "None Entered"; then the treasurer's address and phone are the lead |
| MEC registered committee names in our raw data (`data/raw/mec_summary`, `mec_cd3_b`) | The full name the PAC registered, which often spells out the acronym | `select distinct mecid, committee_name from 'data/raw/mec_summary/*.parquet' where committee_name ilike '%...%'` |
| Contributor addresses in our raw data (`data/raw/mec_cd1_a`: `address_1`, `address_2`, `city`) | The address a PAC writes on its checks | Compare a PAC's most common address with the address on checks from the association or company that is suspected to sponsor it. A shared PO box or suite is strong evidence. A lobbying firm's office or a home address means the PAC has no single industry |
| Sponsor's own website, news coverage | Confirms an address, phone or PAC structure | Used to tie a MEC address or phone to an organization |
| Payer name variants in `fct_campaign_finance` | Filers often write the long form ("MHA Political Action Committee for Health (HEALTHPAC)") | Before adding a keyword, list every payer it would match (see the query at the end) |

Not used yet: FollowTheMoney's API (free with a myFollowTheMoney account, CC BY-NC-SA 3.0) assigns industry
codes to state contributors. FEC committee data (`connected_organization_name`) covers federally registered
PACs only.

## Confirmed sponsors (October 2026)

| Keyword | Industry | Sponsor | Evidence |
| --- | --- | --- | --- |
| `mba` | banking_finance | Missouri Bankers Association, its state PAC and seven regional PACs (Capitol, Gateway, Mark Twain, Ozark, Pony Express, River Heritage, Truman) | MEC [C000405](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C000405): the treasurer's phone (573) 636-8151 is MBA's main number. MBA describes its one-per-region PAC structure on [mobankers.com](https://www.mobankers.com/MBA/MBA/MBAAdvocacy/MBA_PACs.aspx). One payer writes "MBA Gateway Region PAC (Missouri Bankers Association)" |
| `mbwa` | alcohol | Missouri Beer Wholesalers Association | MEC registered name for C000684: "MO Beer Wholesalers Association Wholesalers in Government-PAC". MBWA PAC's checks and the association's checks share 2305 Expressview Dr, Jefferson City (`mec_cd1_a`) |
| `dealers interested in government` | transportation | Missouri Automobile Dealers Association (MADA) | MEC registered name for C000708: "MADA DEALERS INTERESTED IN GOVERNMENT". Some payers write "MADA Dealers Interested in Government" |
| `mha` | health_care | Missouri Hospital Association | "MHA PAC", HEALTHPAC (C000752) and the association's own checks all use PO Box 60, Jefferson City (`mec_cd1_a`: 42, 165 and 316 rows). Payers write "MHA Political Action Committee for Health (HEALTHPAC)" and "MHA (Missouri Hospital Association)". Every payer matching `mha` is hospital-association money |
| `acec` | construction | ACEC Missouri (American Council of Engineering Companies) | MEC [C222134](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C222134) lists ACEC Missouri as its connected organization |
| `pt pac` | health_care | Physical therapists | MEC [C061639](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C061639) "PT-PAC of Missouri", a political action committee. PT-PAC is the physical therapy profession's PAC name ([APTA's PT-PAC](https://ptpac.apta.org/), since 1973). Weaker than the rest: MEC lists no connected organization, and the address is Bardgett & Associates' lobbying office, which manages it |
| `charter communication` | telecom | Charter Communications | Company named outright. Its Missouri PAC files as "Charter Communication Inc MO PAC" (singular), which `charter communications` missed |
| `deloitte`, `ernst young`, `kpmg`, `pricewaterhousecoopers`, `accountants`, `cpas` | accounting | Accounting firms and the AICPA | Named outright |
| `ubs`, `investment company institute` | banking_finance | UBS; the mutual fund trade association | Named outright |
| `honeywell` | defense | Honeywell (aerospace and defense contractor) | Named outright, including "Honeywell Aerospace US LLC Public Affairs Council" |

Confirmed before October 20, 2026 (evidence not recorded at the time): `agc` = AGC of Missouri,
`amec`/`amecpac` = Association of Missouri Electric Cooperatives, `meda` = Missouri Energy Development
Association, `healthpac` = Missouri Hospital Association, `mosfa` = Missouri State Farm Agents, `chipp` =
Carpenters' council, `cheyenne international` = the Decade cigarette maker.

## Confirmed to have no single industry (left unclassified on purpose)

| PAC | Why | Evidence |
| --- | --- | --- |
| ATGS PAC | AT Government Strategies, Armstrong Teasdale's lobbying subsidiary | MEC [C222213](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C222213): 7700 Forsyth Blvd Ste 1800, (314) 621-5070, Armstrong Teasdale's St. Louis office. [Armstrong Teasdale](https://www.armstrongteasdale.com/news/at-government-strategies-adds-two-directors/) describes ATGS as its government-relations subsidiary |
| HBS MO State PAC | Probably Husch Blackwell Strategies, a Jefferson City lobbying firm | MEC [C171213](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C171213): PO Box 1108, Jefferson City. The acronym and city match [Husch Blackwell Strategies](https://molawyersmedia.com/2018/01/09/husch-creates-lobbying-venture/); not confirmed by MEC |
| A Better Missouri PAC, Living Well PAC, Missouri First | Run from a lobbying firm, Bardgett & Associates | Their checks carry 205 E Capitol Ave Ste 100, Jefferson City (`mec_cd1_a`), and one filer wrote "Bardgett & Associates" on that address line |
| Missouri AG PAC, Missouri C PAC, Missouri Senior PAC, Missouri Growth PAC, MO Majority PAC | One treasurer's family of PACs | PO Box 651 / PO Box 555, Perryville (`mec_cd1_a`); MEC [C141393](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C141393) shows the same Perryville box and no connected organization. "AG" is not agriculture |
| MO DSV PAC, RQC PAC | One treasurer's pair | Both at 412 County Road 398, New Bloomfield (`mec_cd1_a`) |
| Real Action PAC, Another Viceroy PAC | One office | MEC [C232460](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C232460) gives Real Action's treasurer (Henry Elster) at 225 S Meramec Ste 325, Clayton, which is Another Viceroy PAC's address in `mec_cd1_a` |
| Catalyst PAC | Probably the Catalyst government-affairs firm, Kansas City | MEC [C171308](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C171308): PO Box 7143, Kansas City; no connected organization |
| RGA, WinRed, Scalise Leadership Fund, Senate Conservatives Fund, AIPAC, candidate committees | Party, conduit, leadership or single-issue committees | Named outright |

## Still unknown

MEC lists no connected organization and no officers for any of these (checked October 2026):

| PAC | MECID | Address on MEC |
| --- | --- | --- |
| Missouri Justice PAC ($880k in one contribution) | [C190952](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C190952) | PO Box 8666, St. Joseph |
| Paladin PAC | [C211760](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C211760) | PO Box 161, Wright City |
| CN-MO PAC | [C232434](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C232434) | 235 E High St Ste 301, Jefferson City |
| POL PAC | [C171247](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C171247) | 221 Bolivar St Ste 301, Jefferson City |
| Shamrock PAC | [C171340](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C171340) | 8 Marne Dr, Lake St. Louis |
| The Rowdy PAC | [C232568](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C232568) | a home address, Jefferson City |
| WPG PAC | [C180495](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C180495) | PO Box 638, Columbia |
| Nexus PAC | [C180599](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C180599) | 714 Locust St, St. Louis |
| MCR PAC | [C253806](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C253806) | PO Box 2221, Jefferson City |
| FCA PAC | [C253591](https://www.mec.mo.gov/MEC/Campaign_Finance/CommInfo.aspx?MECID=C253591) | 16105 Swingley Ridge Rd, Chesterfield |
| MOCS Action | not a MEC committee | PO Box 33009, Kansas City; a 501(c)(4) granted exemption in February 2026 |

## Checking a new keyword

List every payer a keyword would match, and the amount, before adding it:

```python
import duckdb
con = duckdb.connect("data/mogov.duckdb", read_only=True)
con.sql("""
with c as (
  select coalesce(nullif(trim(counterparty_organization), ''), counterparty) as payer, amount
  from marts.fct_campaign_finance
  where direction = 'received' and lower(coalesce(counterparty_type, '')) <> 'individual'
  union all
  select lobbyist_principal, amount from marts.fct_lobbyist_gifts
)
select payer, sum(amount) as amount from c
where ' ' || trim(regexp_replace(lower(payer), '[^a-z0-9]+', ' ', 'g')) || ' ' like '% mba %'
group by 1 order by 2 desc
""").show(max_rows=100)
```
