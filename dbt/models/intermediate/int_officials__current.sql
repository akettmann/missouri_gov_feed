-- Everyone currently holding a Missouri public office that we track, one row per (person, office).
-- official_id: Open States ocd-person id when one exists, else bioguide:<id>, statewide:<office>,
-- or judge:<key> (see int_judges__current).
with os_roles as (
    select *
    from {{ ref('stg_openstates__roles') }}
    where coalesce(end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) >= current_date
),

name_index as (
    -- one Open States person per normalized alternate name
    select
        name_key,
        openstates_id
    from (
        select
            {{ mogov.name_key('alt_name') }} as name_key,
            openstates_id,
            row_number() over (partition by {{ mogov.name_key('alt_name') }} order by openstates_id) as rn
        from {{ ref('stg_openstates__other_names') }}
    ) as ranked
    where rn = 1
),

senators as (
    select
        p.openstates_id as official_id,
        p.openstates_id,
        cast(null as {{ dbt.type_string() }}) as bioguide_id,
        p.full_name,
        p.given_name,
        p.family_name,
        p.party,
        'state' as level,
        'state_senate' as office,
        'State Senator' as office_title,
        r.district,
        r.start_date as current_term_start,
        r.end_date as current_term_end
    from {{ ref('stg_openstates__people') }} as p
    inner join os_roles as r on p.openstates_id = r.openstates_id
    where
        p.folder = 'legislature'
        and r.role_type = 'upper'
),

-- The House roster comes from the House's own XML for the latest regular session (Open States lags).
latest_house_session as (
    select max(session_code) as session_code
    from {{ ref('int_mo_house__member_identity') }}
    where {{ dbt.right('session_code', 1) }} = '1'
),

representatives as (
    select
        m.person_key as official_id,
        m.openstates_id,
        cast(null as {{ dbt.type_string() }}) as bioguide_id,
        coalesce(p.full_name, m.full_name) as full_name,
        coalesce(p.given_name, m.first_name) as given_name,
        coalesce(p.family_name, m.last_name) as family_name,
        coalesce(p.party, m.party) as party,
        'state' as level,
        'state_house' as office,
        'State Representative' as office_title,
        {{ dbt.safe_cast('m.district_number', dbt.type_string()) }} as district,
        cast(null as date) as current_term_start,
        cast(null as date) as current_term_end
    from {{ ref('int_mo_house__member_identity') }} as m
    inner join latest_house_session as s on m.session_code = s.session_code
    left join {{ ref('stg_openstates__people') }} as p on m.openstates_id = p.openstates_id
),

legislators as (
    select * from senators
    union all
    select * from representatives
),

statewide as (
    select
        coalesce(p.openstates_id, 'statewide:' || s.office) as official_id,
        p.openstates_id,
        cast(null as {{ dbt.type_string() }}) as bioguide_id,
        s.name as full_name,
        coalesce(p.given_name, {{ dbt.split_part('s.name', "' '", 1) }}) as given_name,
        coalesce(p.family_name, {{ mogov.regex_extract('s.name', '([^ ]+)$') }}) as family_name,
        s.party,
        'state' as level,
        s.office,
        s.office_title,
        cast(null as {{ dbt.type_string() }}) as district,
        s.term_start as current_term_start,
        s.term_end as current_term_end
    from {{ ref('statewide_officials') }} as s
    -- prefer the person's own Open States record (gives their legislative career) when names match
    left join name_index as n on {{ mogov.name_key('s.name') }} = n.name_key
    left join {{ ref('stg_openstates__people') }} as p on n.openstates_id = p.openstates_id
),

municipal as (
    select
        p.openstates_id as official_id,
        p.openstates_id,
        cast(null as {{ dbt.type_string() }}) as bioguide_id,
        p.full_name,
        p.given_name,
        p.family_name,
        p.party,
        'local' as level,
        r.role_type as office,
        {{ mogov.title_case("r.role_type || ' of ' || replace(r.place_slug, '_', ' ')") }} as office_title,
        cast(null as {{ dbt.type_string() }}) as district,
        r.start_date as current_term_start,
        r.end_date as current_term_end
    from {{ ref('stg_openstates__people') }} as p
    inner join (
        select
            *,
            {{ mogov.regex_extract('jurisdiction', 'place:([a-z_]+)') }} as place_slug
        from os_roles
    ) as r on p.openstates_id = r.openstates_id
    where p.folder = 'municipalities'
),

federal as (
    select
        'bioguide:' || bioguide_id as official_id,
        cast(null as {{ dbt.type_string() }}) as openstates_id,
        bioguide_id,
        full_name,
        given_name,
        family_name,
        party,
        'federal' as level,
        case latest_term_type when 'sen' then 'us_senate' else 'us_house' end as office,
        case latest_term_type when 'sen' then 'U.S. Senator' else 'U.S. Representative' end as office_title,
        latest_term_district as district,
        latest_term_start as current_term_start,
        latest_term_end as current_term_end
    from {{ ref('stg_congress__legislators') }}
    where is_current and latest_term_state = 'MO'
),

judges as (
    select
        official_id,
        cast(null as {{ dbt.type_string() }}) as openstates_id,
        cast(null as {{ dbt.type_string() }}) as bioguide_id,
        full_name,
        given_name,
        family_name,
        cast(null as {{ dbt.type_string() }}) as party,
        level,
        office,
        office_title,
        district,
        current_term_start,
        current_term_end
    from {{ ref('int_judges__current') }}
),

{% set cols = 'official_id, openstates_id, bioguide_id, full_name, given_name, family_name, party, level, office,
    office_title, district, current_term_start, current_term_end' %}
unioned as (
    select {{ cols }} from legislators
    union all
    select {{ cols }} from statewide
    union all
    select {{ cols }} from municipal
    union all
    select {{ cols }} from federal
    union all
    select {{ cols }} from judges
)

select * from unioned
