-- Past and present offices held by each current official, from every source that records careers.
-- The same term can arrive from several sources; the most authoritative copy is kept.
with os_roles as (
    -- roles under every Open States id the person has had, not only today's
    select
        coalesce(x.person_id, r.openstates_id) as person_id,
        r.role_type,
        r.district,
        r.jurisdiction,
        r.start_date,
        r.end_date
    from {{ ref('stg_openstates__roles') }} as r
    left join {{ ref('int_officials__person_ids') }} as x on r.openstates_id = x.alias_id
),

os as (
    select
        o.official_id,
        case r.role_type
            when 'upper' then 'State Senator'
            when 'lower' then 'State Representative'
            else {{ mogov.title_case("replace(r.role_type, '_', ' ')") }}
        end as office_title,
        r.district,
        r.jurisdiction,
        r.start_date,
        r.end_date,
        'openstates' as source,
        3 as source_rank
    from {{ ref('int_officials__current') }} as o
    inner join os_roles as r on o.official_id = r.person_id
),

congress as (
    select
        o.official_id,
        case t.term_type when 'sen' then 'U.S. Senator' else 'U.S. Representative' end as office_title,
        t.district,
        'ocd-jurisdiction/country:us/state:' || lower(t.state) as jurisdiction,
        t.start_date,
        t.end_date,
        'congress-legislators' as source,
        2 as source_rank
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('stg_congress__terms') }} as t on o.bioguide_id = t.bioguide_id
),

statewide as (
    select
        o.official_id,
        s.office_title,
        cast(null as {{ dbt.type_string() }}) as district,
        'ocd-jurisdiction/country:us/state:mo/government' as jurisdiction,
        s.term_start as start_date,
        s.term_end as end_date,
        'statewide_officials seed' as source,
        1 as source_rank
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('statewide_officials') }} as s on o.office = s.office
),

judges as (
    select
        o.official_id,
        a.appointment_title || ', ' || a.court_name as office_title,
        cast(null as {{ dbt.type_string() }}) as district,
        'fjc' as jurisdiction,
        a.commission_date as start_date,
        a.termination_date as end_date,
        'fjc' as source,
        1 as source_rank
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('stg_fjc__appointments') }} as a on o.official_id = 'fjc:' || a.fjc_nid
),

wikidata as (
    select
        q.official_id,
        f.value as office_title,
        f.qualifier as district,
        'wikidata' as jurisdiction,
        f.start_date,
        f.end_date,
        'wikidata' as source,
        4 as source_rank
    from {{ ref('int_officials__wikidata') }} as q
    inner join {{ ref('stg_wikidata__facts') }} as f on q.qid = f.qid
    where f.fact_kind = 'position held'
),

courtlistener as (
    select
        official_id,
        case
            when organization is not null and position_title <> organization then position_title || ', ' || organization
            else position_title
        end as office_title,
        cast(null as {{ dbt.type_string() }}) as district,
        'courtlistener' as jurisdiction,
        start_date,
        end_date,
        'courtlistener' as source,
        5 as source_rank
    from {{ ref('int_courtlistener__official_positions') }}
),

-- Earlier stretches of the statewide offices a current official has held (#741): Malek's 2023 appointment as Treasurer
-- before the term he was elected to in 2025, Fitzpatrick's 2019-2023 Treasurer term, Schmitt as Attorney General.
-- Derived from the Official Manual listings with exact dates from statewide_office_handovers (int_statewide__terms),
-- not from a second hand-kept list. The open term ends where the seed's current term starts. int_statewide__terms
-- only gives an official_id when the person's known service corroborates the name match (#760), so a namesake of a
-- nineteenth-century governor gets no row. A term another source also records is collapsed by deduped below.
statewide_past as (
    select
        t.official_id,
        s.office_title,
        cast(null as {{ dbt.type_string() }}) as district,
        'ocd-jurisdiction/country:us/state:mo/government' as jurisdiction,
        t.term_start as start_date,
        case when t.term_end_year is null then s.term_start else t.term_end end as end_date,
        'official manual statewide listing' as source,
        2 as source_rank
    from {{ ref('int_statewide__terms') }} as t
    inner join {{ ref('statewide_officials') }} as s on t.office = s.office
    where
        t.official_id is not null
        and t.term_start < case when t.term_end_year is null then s.term_start else t.term_end end
),

-- State judges: appointment / election sentences from their Official Manual biography
judge_bio_events as (
    {% for label, pattern in [
        ('appointed', '([Aa]ppointed [^.]*(judge|[Cc]ourt)[^.]*[0-9]{4})'),
        ('elected', '(([Ee]lected|[Rr]etained|[Rr]e-elected) [^.]*(judge|voters|term|[Cc]ourt)[^.]*[0-9]{4})'),
        ('prior', '((Served|served) as [^.]*(prosecut|attorney|judge|commissioner)[^.]*)'),
    ] %}
        select
            b.official_id,
            {{ mogov.regex_extract('b.bio_text', pattern) }} as office_title,
            cast(null as {{ dbt.type_string() }}) as district,
            'mo judiciary' as jurisdiction,
            {%- set year = mogov.regex_extract(mogov.regex_extract('b.bio_text', pattern), '([0-9]{4})') %}
            {{ dbt.safe_cast(dbt.concat([year, "'-01-01'"]), 'date') }} as start_date,
            cast(null as date) as end_date,
            b.source,
            6 as source_rank
        from {{ ref('int_officials__bios') }} as b
        where b.source like 'Missouri Official Manual%' and b.official_id like 'mojudge:%'
        {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

{% set cols = 'official_id, office_title, district, jurisdiction, start_date, end_date, source, source_rank' %}
all_terms as (
    select {{ cols }} from os
    union all
    select {{ cols }} from congress
    union all
    select {{ cols }} from statewide
    union all
    select {{ cols }} from statewide_past
    union all
    select {{ cols }} from judges
    union all
    select {{ cols }} from wikidata
    union all
    select {{ cols }} from courtlistener
    union all
    select {{ cols }} from judge_bio_events
    where office_title is not null
),

ranked as (
    select
        *,
        {{ mogov.statewide_office_key('office_title') }} as office_key,
        row_number() over (
            partition by official_id, office_title, start_date
            order by
                source_rank asc,
                source asc,
                -- the open term (null end) first, then the latest end: a renewed or current term beats a stale copy
                coalesce(end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) desc,
                district,
                jurisdiction asc
        ) as rn
    from all_terms
),

best as (
    select *
    from ranked
    where rn = 1
),

-- One statewide term arrives from several sources under different titles ("Governor" in the seed, "Governor of
-- Missouri" in Wikidata) and dates a day or two apart. A row is dropped when the same official has a better-ranked row
-- for the same statewide office (statewide_office_key) starting within a month of it. The best-ranked row is kept;
-- the key ends in the title and the start date so the choice is the same on every run.
deduped as (
    select b.*
    from best as b
    where not exists (
        select 1
        from best as o
        where
            o.official_id = b.official_id
            and o.office_key = b.office_key
            and {{ mogov.is_statewide_office_key('o.office_key') }}
            and not (o.office_title = b.office_title and o.start_date = b.start_date)
            and abs({{ dbt.datediff('o.start_date', 'b.start_date', 'day') }}) <= 31
            and (
                o.source_rank < b.source_rank
                or (
                    o.source_rank = b.source_rank
                    and (
                        o.source < b.source
                        or (
                            o.source = b.source
                            and (
                                o.start_date < b.start_date
                                or (o.start_date = b.start_date and o.office_title < b.office_title)
                            )
                        )
                    )
                )
            )
    )
)

select
    official_id,
    office_title,
    district,
    jurisdiction,
    start_date,
    end_date,
    source
from deduped
