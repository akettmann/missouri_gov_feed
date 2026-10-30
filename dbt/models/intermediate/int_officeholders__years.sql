-- Who held each tracked office in each year, for the offices whose past holders have dated records:
--   state_house    the House's own roster for each session year (int_mo_house__member_identity). Members who
--                  left mid-session are missing from that session's end-of-session list.
--   state_senate   Open States seat-terms (int_mo_legislators__seats, which dates them from the Senate journal
--                  roll calls where Open States has no start or a wrong end). A year is kept only when all 34
--                  districts have a dated holder, so a partial year doesn't pass as the full Senate.
--   us_house, us_senate                 congress-legislators terms for Missouri
--   us_district_court, us_court_of_appeals   FJC commissions on the E.D./W.D. Mo. district courts, and
--                  Eighth Circuit judges whose FJC career mentions Missouri (as int_judges__federal)
-- A term counts for a year when it runs past January 15 of it, so a hand-over in the first days of January
-- (Congress turns over on January 3) doesn't list both the outgoing and the incoming holder.
-- Years are those with a House roster. A roster row is dropped when the roster outlived the member, by either of two
-- tests: the person's last roll-call vote was before the year's handover (any row, #491; only in a year with House
-- roll calls on or after the handover, so a roster stays whole until that year's roll calls are loaded), or the row's
-- Open States person has a last House term that ended before the handover (only rows whose roster member carries an
-- Open States id: the name-anchor override, #152).
-- Statewide officers, mayors and state judges have no dated past rosters here.
-- person keys match dim_official.official_id, so a past holder who serves today links to their profile.
-- official_id is the stable person id; openstates_id is the Open States record the senate row came from (null for
-- other sources), kept so rpt_officeholders_by_year can find that record's folder. session_code is the House
-- session file (e.g. 251, 253) listing the member, the earliest one in the year; null for other sources.
with years as (
    select distinct
        session_year as year,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('session_year', dbt.type_string()), "'-01-15'"]), 'date') }}
            as handover_date,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('session_year', dbt.type_string()), "'-12-31'"]), 'date') }}
            as year_end
    from {{ ref('int_mo_house__member_identity') }}
),

-- the end of each person's last Open States House term. A House roster can keep listing a member after they left
-- (Rebecca Roeber, HD34, died 2019-07-30 yet the 2020 sessions still list her; the seat sat vacant until January
-- 2021, #152), so a roster row counts only while that term runs past the year's handover, the rule the other
-- offices use. Only rows whose roster member carries an Open States id (the name-anchor override assigns it): a
-- row matched by member id alone (Lauren Arthur, 2017-2018, whose Open States House term stops in 2016 though she
-- voted through 2018) has no Open States term to hold it to; the roll calls below cover those.
last_house_term as (
    select
        person_id,
        max(end_date) as last_end_date
    from {{ ref('int_mo_legislators__seats') }}
    where chamber = 'lower'
    group by person_id
),

-- the date of each person's last roll-call vote. Roll calls, not Open States, say when a member stopped: Scott
-- Fitzpatrick (HD158) cast his last vote on 2019-01-09 and became State Treasurer, HD158 had no member until
-- Scott Cupps in 2020, and the roster still lists him for 2019 because the seat match found no Open States
-- person for his 2019 row (#491). A person with no attributed votes has no entry and is never dropped by this
-- test. The Speaker is on every roll call (house_speakers), so a Speaker's last vote is the end of the term.
last_house_vote as (
    select
        person_key,
        max(vote_date) as last_vote_date
    from {{ ref('int_mo_house__votes') }}
    where person_key is not null
    group by person_key
),

-- the roster years with House roll calls on or after the handover. The vote test applies only to these: in January,
-- before the year's first roll calls are loaded, every returning member's last vote is still in the previous
-- year, and the test would drop the whole roster. A year whose roll calls end before the handover has no
-- evidence to hold anyone to.
rollcall_years as (
    select distinct y.year
    from years as y
    inner join {{ ref('int_mo_house__votes') }} as v on y.handover_date <= v.vote_date and y.year_end >= v.vote_date
),

house as (
    select
        m.session_year as year,
        m.person_key as official_id,
        coalesce(p.full_name, m.full_name) as full_name,
        m.party,
        'state' as level,
        'state_house' as office,
        'State Representative' as office_title,
        {{ dbt.safe_cast('m.district_number', dbt.type_string()) }} as district,
        'mo_house roster' as source,
        cast(null as {{ dbt.type_string() }}) as openstates_id,
        m.session_code
    from {{ ref('int_mo_house__member_identity') }} as m
    left join {{ ref('stg_openstates__people') }} as p on m.openstates_id = p.openstates_id
    inner join years as y on m.session_year = y.year
    left join last_house_term as t on m.person_key = t.person_id
    left join last_house_vote as v on m.person_key = v.person_key
    left join rollcall_years as rc on m.session_year = rc.year
    where
        (m.openstates_id is null or t.last_end_date is null or t.last_end_date > y.handover_date)
        and (v.last_vote_date is null or rc.year is null or v.last_vote_date >= y.handover_date)
),

senate_terms as (
    select
        y.year,
        s.person_id as official_id,
        s.full_name,
        s.party,
        'state' as level,
        'state_senate' as office,
        'State Senator' as office_title,
        {{ dbt.safe_cast('s.district_number', dbt.type_string()) }} as district,
        'openstates' as source,
        s.openstates_id,
        cast(null as {{ dbt.type_string() }}) as session_code
    from {{ ref('int_mo_legislators__seats') }} as s
    inner join years as y on s.start_date <= y.year_end and s.end_date > y.handover_date
    where
        s.chamber = 'upper'
        -- an undated start in the journal years is dated from the senator's first vote there (start_quality
        -- first_vote, #522); the first year of any left undated is unknown
        and s.start_quality <> 'undated'
),

senate_complete_years as (
    select year
    from senate_terms
    group by year
    having count(distinct district) = 34
),

senate as (
    select t.*
    from senate_terms as t
    inner join senate_complete_years as c on t.year = c.year
),

congress as (
    select
        y.year,
        'bioguide:' || t.bioguide_id as official_id,
        t.full_name,
        t.party,
        'federal' as level,
        case t.term_type when 'sen' then 'us_senate' else 'us_house' end as office,
        case t.term_type when 'sen' then 'U.S. Senator' else 'U.S. Representative' end as office_title,
        t.district,
        'congress-legislators' as source,
        cast(null as {{ dbt.type_string() }}) as openstates_id,
        cast(null as {{ dbt.type_string() }}) as session_code
    from {{ ref('stg_congress__terms') }} as t
    inner join years as y on t.start_date <= y.year_end and t.end_date > y.handover_date
    where t.state = 'MO'
),

judge_terms as (
    select
        y.year,
        a.fjc_nid,
        trim(
            coalesce(a.given_name, '') || ' ' || coalesce(a.middle_name || ' ', '') || a.family_name
            || coalesce(' ' || a.suffix, '')
        ) as full_name,
        a.court_name,
        case
            when a.court_name = 'U.S. District Court for the Eastern District of Missouri' then 'moed'
            when a.court_name = 'U.S. District Court for the Western District of Missouri' then 'mowd'
            when a.court_name = 'U.S. Court of Appeals for the Eighth Circuit' then 'ca8'
        end as court_key,
        a.professional_career
    from {{ ref('stg_fjc__appointments') }} as a
    inner join years as y
        on
            a.commission_date <= y.year_end
            and coalesce(a.termination_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) > y.handover_date
),

-- one row per judge and year; some district judges hold joint E.D./W.D. Missouri commissions
judges as (
    select
        year,
        'fjc:' || fjc_nid as official_id,
        max(full_name) as full_name,
        cast(null as {{ dbt.type_string() }}) as party,
        'federal' as level,
        max(case court_key when 'ca8' then 'us_court_of_appeals' else 'us_district_court' end) as office,
        case
            when max(case when court_key = 'ca8' then 1 else 0 end) = 1
                then 'Judge, U.S. Court of Appeals for the Eighth Circuit (Missouri career ties)'
            when count(distinct court_key) > 1
                then 'Judge, U.S. District Courts for the Eastern and Western Districts of Missouri'
            else 'Judge, ' || max(court_name)
        end as office_title,
        case when count(distinct court_key) > 1 then 'moed+mowd' else max(court_key) end as district,
        'fjc' as source,
        cast(null as {{ dbt.type_string() }}) as openstates_id,
        cast(null as {{ dbt.type_string() }}) as session_code
    from judge_terms
    where
        court_key is not null
        and (court_key <> 'ca8' or professional_career like '%Missouri%')
    group by year, fjc_nid
),

{% set cols = 'year, official_id, full_name, party, level, office, office_title, district, source, '
    ~ 'openstates_id, session_code' %}
unioned as (
    select {{ cols }} from house
    union all
    select {{ cols }} from senate
    union all
    select {{ cols }} from congress
    union all
    select {{ cols }} from judges
)

-- a person's consecutive terms (or Open States plus a seed correction) can both overlap a year
select
    year,
    official_id,
    office,
    max(full_name) as full_name,
    max(party) as party,
    max(level) as level,
    max(office_title) as office_title,
    max(district) as district,
    max(source) as source,
    max(openstates_id) as openstates_id,
    -- a House member listed in a regular and a special session keeps the earliest file (the regular one, if listed)
    min(session_code) as session_code
from unioned
group by year, official_id, office
