-- MEC itemized expenditures by Missouri committees (TAP mirror, 2011-2022): includes contributions the
-- committee made to other candidates and committees.
-- payee_name (#85): TAP's own payee_name column holds only the last name for an individual payee, which merged
-- different people with a shared surname. A payee with a usable first and last name is "First Last"; anything else
-- keeps TAP's payee_name, then company, then the partial person name. Placeholders ('~', '-', one character, no
-- letter or number) are dropped with the same rules as contributions (macros/names.sql).
select
    cd3_b_id as record_id,
    mecid as mec_committee_id,
    committee_name,
    coalesce(
        case
            when {{ mogov.name_part('first_name') }} is not null and {{ mogov.name_part('last_name') }} is not null
                then {{ mogov.person_name('first_name', 'last_name') }}
        end,
        {{ mogov.clean_name('payee_name') }},
        {{ mogov.clean_name('company') }},
        {{ mogov.person_name('first_name', 'last_name') }}
    ) as payee_name,
    purpose,
    expenditure_type,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ dbt.safe_cast('date_clean', 'date') }} as expenditure_date,
    {{ dbt.safe_cast('year_clean', dbt.type_int()) }} as expenditure_year,
    city_final as payee_city,
    state_norm as payee_state,
    report
from {{ source('tap_mec', 'expenditures') }}
where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
