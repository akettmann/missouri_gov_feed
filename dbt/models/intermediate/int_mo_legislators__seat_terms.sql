-- Every Missouri legislative seat-term in Open States (current and retired people), keyed for matching:
-- chamber, district number, surname key, and date range (open-ended where Open States has no date).
-- One row per Open States id as given, so a person Open States holds twice has rows under both ids;
-- int_mo_legislators__seats adds the stable person_id.
-- Two corrections to Open States:
--   * a term starting in January counts from January 1. Open States starts the 2017 class on January 11,
--     but the session (and their votes) began January 4.
--   * seed legislator_seat_corrections adds terms Open States lacks or cuts short (senators who left
--     mid-term for statewide office), each with its source.
-- source_start_date/source_end_date carry the dates exactly as Open States (or the seed) gives them, without those
-- adjustments (null start when undated; end 9999-12-31 while open).
-- Quality flags (#656) say how far each date can be trusted; they change no other column, so consumers can move to
-- them one by one. start_quality is dated, undated (no Open States start) or placeholder (an Open States start on
-- January 1, never a real start); known_start_date is the as-given start only when dated. end_quality is open, dated,
-- conflicts_with_journal (a Senate end the journal roll calls contradict: the terms int_mo_legislators__seats
-- re-dates) or conflicts_with_roster (a House end the House's session rosters contradict), with the evidence dates
-- behind it. The column docs give each rule. The evidence is read from staging (stg_mo_senate__votes,
-- stg_mo_house__members), never from a model carrying person_id: this model is upstream of int_officials__person_ids.
with roles as (
    select
        openstates_id,
        role_type as chamber,
        district,
        start_date,
        end_date,
        false as is_seed
    from {{ ref('stg_openstates__roles') }}
    where role_type in ('upper', 'lower')
    union all
    select
        openstates_id,
        chamber,
        {{ dbt.safe_cast('district', dbt.type_string()) }} as district,
        {{ dbt.safe_cast('start_date', 'date') }} as start_date,
        {{ dbt.safe_cast('end_date', 'date') }} as end_date,
        true as is_seed
    from {{ ref('legislator_seat_corrections') }}
),

terms as (
    select
        r.openstates_id,
        p.full_name,
        p.family_name,
        p.party,
        {{ mogov.name_key('p.family_name') }} as surname_key,
        {{ mogov.name_key('p.full_name') }} as full_name_key,
        r.chamber,
        {{ dbt.safe_cast('r.district', dbt.type_int()) }} as district_number,
        case
            when r.start_date is null then {{ dbt.safe_cast("'1900-01-01'", 'date') }}
            when extract(month from r.start_date) = 1 then {{ dbt.date_trunc('year', 'r.start_date') }}
            else r.start_date
        end as start_date,
        coalesce(r.end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date,
        -- the dates exactly as Open States (or the seed) gives them, without the January-1 or 1900 adjustments above:
        -- what an overlap test between two ids needs (null start when undated; end 9999-12-31 while open)
        {{ dbt.safe_cast('r.start_date', 'date') }} as source_start_date,
        coalesce(r.end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as source_end_date,
        case
            when r.is_seed and r.start_date is not null then 'dated'
            when r.start_date is null then 'undated'
            when extract(month from r.start_date) = 1 and extract(day from r.start_date) = 1 then 'placeholder'
            else 'dated'
        end as start_quality
    from roles as r
    inner join {{ ref('stg_openstates__people') }} as p on r.openstates_id = p.openstates_id
),

-- Senate journal evidence ------------------------------------------------------------------------------------------
senate_votes as (
    select
        vote_id,
        senator_token,
        vote_date,
        token_district,
        {{ mogov.name_key('token_name') }} as token_key
    from {{ ref('stg_mo_senate__votes') }}
),

senate_candidates as (
    select
        v.vote_id,
        v.senator_token,
        v.vote_date,
        t.surname_key,
        t.district_number
    from senate_votes as v
    inner join terms as t
        on
            t.chamber = 'upper'
            and v.vote_date between t.start_date and t.end_date
            and (v.token_key = t.surname_key or v.token_key like '% ' || t.surname_key)
            and (v.token_district is null or v.token_district = t.district_number)
),

-- a token naming one (surname key, district) on its date: two Open States ids of one person in one seat agree on both
senate_tokens as (
    select
        vote_id,
        senator_token,
        vote_date,
        max(surname_key) as surname_key,
        max(district_number) as district_number
    from senate_candidates
    group by vote_id, senator_token, vote_date
    having
        count(distinct {{ dbt.concat(['surname_key', "'|'", dbt.safe_cast('district_number', dbt.type_string())]) }})
        = 1
),

-- With no journal loaded first_date is the open-end date, so no term runs "into the journal years".
journal as (
    select
        coalesce(min(vote_date), {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as first_date,
        coalesce(max(vote_date), {{ dbt.safe_cast("'1900-01-01'", 'date') }}) as last_date
    from senate_votes
),

journal_years as (
    select distinct extract(year from vote_date) as yr
    from senate_votes
),

senate_term_years as (
    select
        t.openstates_id,
        t.district_number,
        t.start_date,
        t.end_date,
        extract(year from case when t.start_date > j.first_date then t.start_date else j.first_date end) as year_from,
        extract(
            year from case
                when t.end_date < {{ dbt.safe_cast("'9999-12-31'", 'date') }} then t.end_date
                else j.last_date
            end
        ) as year_to
    from terms as t
    cross join journal as j
    where t.chamber = 'upper'
),

-- every year of the term the journals could cover has journal votes (a partial raw load leaves the term unflagged)
senate_coverage as (
    select
        t.openstates_id,
        t.district_number,
        t.start_date,
        t.end_date,
        count(y.yr) >= max(t.year_to - t.year_from + 1) as journal_covers_term
    from senate_term_years as t
    left join journal_years as y on y.yr between t.year_from and t.year_to
    group by t.openstates_id, t.district_number, t.start_date, t.end_date
),

senate_term_tokens as (
    select
        t.openstates_id,
        t.district_number,
        t.start_date,
        t.end_date,
        min(v.vote_date) as first_token_date,
        max(v.vote_date) as last_token_date
    from terms as t
    inner join senate_tokens as v
        on
            t.surname_key = v.surname_key
            and t.district_number = v.district_number
            and v.vote_date between t.start_date and t.end_date
    where t.chamber = 'upper'
    group by t.openstates_id, t.district_number, t.start_date, t.end_date
),

senate_evidence as (
    select
        t.openstates_id,
        t.district_number,
        t.start_date,
        t.end_date,
        v.first_token_date,
        v.last_token_date,
        t.end_date < {{ dbt.safe_cast("'9999-12-31'", 'date') }}
        and c.journal_covers_term
        and (
            {{ dbt.dateadd('year', 1, 'v.last_token_date') }} < t.end_date
            or (v.last_token_date is null and t.end_date >= j.first_date)
        ) as conflicts_with_journal
    from terms as t
    cross join journal as j
    inner join senate_coverage as c
        on
            t.openstates_id = c.openstates_id
            and t.district_number = c.district_number
            and t.start_date = c.start_date
            and t.end_date = c.end_date
    left join senate_term_tokens as v
        on
            t.openstates_id = v.openstates_id
            and t.district_number = v.district_number
            and t.start_date = v.start_date
            and t.end_date = v.end_date
    where t.chamber = 'upper'
),

-- House roster evidence --------------------------------------------------------------------------------------------
roster as (
    select distinct
        session_year,
        district_number,
        -- without a generational suffix ("Franks Jr." is Open States' Franks)
        {{ mogov.surname_key('last_name') }} as last_name_key
    from {{ ref('stg_mo_house__members') }}
    where district_number is not null
),

roster_years as (
    select distinct
        session_year,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('session_year', dbt.type_string()), "'-01-15'"]), 'date') }}
            as handover_date,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('session_year', dbt.type_string()), "'-05-31'"]), 'date') }}
            as session_end_date,
        {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('session_year', dbt.type_string()), "'-12-31'"]), 'date') }}
            as year_end_date
    from roster
),

-- (House term, roster row) where the district's list has a member with the term's surname: equal but for spacing
-- and generational suffixes ("Van Schoiack" and "Franks Jr." are Open States' VanSchoiack and Franks), or the last
-- word of a compound surname on the roster
roster_match as (
    select
        t.openstates_id,
        t.district_number,
        t.start_date,
        t.end_date,
        r.last_name_key,
        y.session_year,
        y.handover_date,
        y.year_end_date
    from terms as t
    inner join roster as r
        on
            t.district_number = r.district_number
            and (
                {{ dbt.replace('r.last_name_key', "' '", "''") }}
                = {{ dbt.replace(mogov.surname_key('t.family_name'), "' '", "''") }}
                or r.last_name_key like '% ' || {{ mogov.surname_key('t.family_name') }}
            )
    inner join roster_years as y on r.session_year = y.session_year
    where t.chamber = 'lower'
),

-- the roster lists the term's surname in a year after the term ended (before that year's handover), and no Open
-- States House term matching that roster member runs into the year; flag the latest such term that ended before it
roster_after_end as (
    select
        a.openstates_id,
        a.district_number,
        a.start_date,
        a.end_date,
        a.session_year
    from roster_match as a
    where
        a.end_date < a.handover_date
        and not exists (
            select 1
            from roster_match as o
            where
                o.session_year = a.session_year
                and o.district_number = a.district_number
                and o.last_name_key = a.last_name_key
                and o.start_date <= o.year_end_date
                and o.end_date > o.handover_date
        )
        and not exists (
            select 1
            from roster_match as later
            where
                later.session_year = a.session_year
                and later.district_number = a.district_number
                and later.last_name_key = a.last_name_key
                and later.end_date > a.end_date
                and later.end_date < later.handover_date
        )
),

-- roster years a House term should be on the end-of-session list: it runs from before the handover to past May 31
house_expected as (
    select
        t.openstates_id,
        t.district_number,
        t.start_date,
        t.end_date,
        y.session_year,
        exists(
            select 1
            from roster_match as s
            where
                s.openstates_id = t.openstates_id
                and s.district_number = t.district_number
                and s.start_date = t.start_date
                and s.end_date = t.end_date
                and s.session_year = y.session_year
        ) as is_listed
    from terms as t
    inner join roster_years as y
        on t.start_date <= y.handover_date and t.end_date >= y.session_end_date
    where
        t.chamber = 'lower'
        -- a district missing from a year's list (vacant at the session's end) is no evidence either way
        and exists (
            select 1
            from roster as r
            where r.session_year = y.session_year and r.district_number = t.district_number
        )
),

-- expected years from the last year the term is listed on: all unlisted ones count when every later one is unlisted
roster_unlisted as (
    select
        e.openstates_id,
        e.district_number,
        e.start_date,
        e.end_date,
        e.session_year
    from house_expected as e
    where
        not e.is_listed
        and not exists (
            select 1
            from house_expected as l
            where
                l.openstates_id = e.openstates_id
                and l.district_number = e.district_number
                and l.start_date = e.start_date
                and l.end_date = e.end_date
                and l.is_listed
                and l.session_year > e.session_year
        )
),

roster_conflicts as (
    select
        openstates_id,
        district_number,
        start_date,
        end_date,
        min(session_year) as first_year,
        max(session_year) as last_year
    from (
        select * from roster_after_end
        union all
        select * from roster_unlisted
    ) as c
    group by openstates_id, district_number, start_date, end_date
)

select
    t.openstates_id,
    t.full_name,
    t.family_name,
    t.party,
    t.surname_key,
    t.full_name_key,
    t.chamber,
    t.district_number,
    t.start_date,
    t.end_date,
    t.source_start_date,
    t.source_end_date,
    t.start_quality,
    case when t.start_quality = 'dated' then t.source_start_date end as known_start_date,
    case
        when s.conflicts_with_journal then 'conflicts_with_journal'
        when rc.openstates_id is not null then 'conflicts_with_roster'
        when t.source_end_date = {{ dbt.safe_cast("'9999-12-31'", 'date') }} then 'open'
        else 'dated'
    end as end_quality,
    case
        when t.chamber = 'upper' then s.first_token_date
        else {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('rc.first_year', dbt.type_string()), "'-01-01'"]), 'date') }}
    end as evidence_first_date,
    case
        when t.chamber = 'upper' then s.last_token_date
        else {{ dbt.safe_cast(dbt.concat([dbt.safe_cast('rc.last_year', dbt.type_string()), "'-12-31'"]), 'date') }}
    end as evidence_last_date
from terms as t
left join senate_evidence as s
    on
        t.openstates_id = s.openstates_id
        and t.district_number = s.district_number
        and t.start_date = s.start_date
        and t.end_date = s.end_date
left join roster_conflicts as rc
    on
        t.openstates_id = rc.openstates_id
        and t.district_number = rc.district_number
        and t.start_date = rc.start_date
        and t.end_date = rc.end_date
