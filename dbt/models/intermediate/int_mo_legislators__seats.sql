-- Every Missouri legislative seat-term in Open States (current and retired people), keyed for matching:
-- chamber, district number, surname key, and date range (open-ended where Open States has no date).
select
    r.openstates_id,
    p.full_name,
    p.family_name,
    p.party,
    {{ mogov.name_key('p.family_name') }} as surname_key,
    {{ mogov.name_key('p.full_name') }} as full_name_key,
    r.role_type as chamber,
    {{ dbt.safe_cast('r.district', dbt.type_int()) }} as district_number,
    coalesce(r.start_date, {{ dbt.safe_cast("'1900-01-01'", 'date') }}) as start_date,
    coalesce(r.end_date, {{ dbt.safe_cast("'9999-12-31'", 'date') }}) as end_date
from {{ ref('stg_openstates__roles') }} as r
inner join {{ ref('stg_openstates__people') }} as p on r.openstates_id = p.openstates_id
where r.role_type in ('upper', 'lower')
