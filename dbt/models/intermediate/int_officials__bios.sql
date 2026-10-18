-- One biography text per current official where a source has one: Official Manual (legislators),
-- MO House XML (representatives), FJC professional career (federal judges), Open States (others).
with bluebook as (
    select
        o.official_id,
        b.bio_text,
        'Missouri Official Manual ' || b.edition as source,
        b.source_url
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('int_bluebook__bios') }} as b
        on
            o.office = case b.chamber when 'upper' then 'state_senate' else 'state_house' end
            and {{ dbt.safe_cast('o.district', dbt.type_int()) }} = b.district_number
            and b.name_key like '%' || {{ mogov.name_key('o.family_name') }} || '%'
),

house_xml as (
    select
        m.person_key as official_id,
        m.biography as bio_text,
        'MO House member page ' || m.session_code as source,
        'https://house.mo.gov/MemberDetails.aspx?district=' || m.district as source_url
    from {{ ref('int_mo_house__member_identity') }} as m
    where
        m.biography is not null
        and m.session_code = (select max(i.session_code) from {{ ref('int_mo_house__member_identity') }} as i)
),

state_judges as (
    select
        o.official_id,
        b.bio_text,
        'Missouri Official Manual ' || b.edition as source,
        b.source_url
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('int_bluebook__judge_bios') }} as b
        on {{ mogov.name_key('o.full_name') }} = b.name_key
    where o.office like 'mo_%'
),

fjc as (
    select
        official_id,
        professional_career as bio_text,
        'FJC Biographical Directory' as source,
        'https://www.fjc.gov/history/judges' as source_url
    from {{ ref('int_judges__federal') }}
),

openstates as (
    select
        o.official_id,
        r.biography as bio_text,
        'Open States' as source,
        cast(null as {{ dbt.type_string() }}) as source_url
    from {{ ref('int_officials__current') }} as o
    inner join {{ ref('stg_openstates__current_roster') }} as r on o.openstates_id = r.openstates_id
    where r.biography is not null
)

select * from bluebook
union all
select * from house_xml
union all
select * from state_judges
union all
select * from fjc
union all
select * from openstates
