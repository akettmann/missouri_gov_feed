-- MEC itemized expenditures by Missouri committees (TAP mirror, 2011-2022): includes contributions the
-- committee made to other candidates and committees.
-- payee_name (#85): TAP's own payee_name column is just coalesce(last_name, first_name, company), so it is not an
-- independent source and is not used. A payee with a company keeps that company, which stops a contact's name
-- (the person at the vendor) replacing the vendor. When the company only repeats the person's last name or "First
-- Last" (compared ignoring case and spaces), the payee is the individual, so "First Last" is used instead; this
-- keeps different people sharing a surname apart. Only a one-word last name is compared that way: a last name of
-- several words ('Mulligan Printing' typed into the last-name box) is the vendor itself, so the company wins and
-- the contact's first name is not prefixed. With no usable company the payee is "First Last", then the
-- partial person name (first or last alone). Placeholders ('~', '-', no letter or number) are dropped, and a
-- whole name (company) of one character is dropped; a part of a person's name keeps initials ('J Roe'). All-digit
-- name parts are dropped. When the last name is the first name, or starts with the first name followed by a space
-- (an organization typed into both boxes: 'USPS' / 'USPS'), the last name alone is used. Built from the shared
-- macros in macros/names.sql, which stg_tap_mec__contributions also uses.
with

names as (
    select
        *,
        {{ mogov.clean_name('company') }} as company_clean,
        case
            when {{ mogov.name_part('first_name') }} is not null and {{ mogov.name_part('last_name') }} is not null
                then
                    case
                        when
                            lower({{ mogov.name_part('last_name') }}) = lower({{ mogov.name_part('first_name') }})
                            or left(
                                lower({{ mogov.name_part('last_name') }}),
                                length({{ mogov.name_part('first_name') }}) + 1
                            )
                            = lower({{ mogov.name_part('first_name') }}) || ' '
                            then {{ mogov.name_part('last_name') }}
                        else {{ mogov.person_name('first_name', 'last_name') }}
                    end
        end as full_name,
        {{ mogov.person_name('first_name', 'last_name') }} as person_name_any,
        case
            when {{ mogov.name_part('last_name') }} not like '% %'
                then lower({{ mogov.name_part('last_name') }})
        end as last_key
    from {{ source('tap_mec', 'expenditures') }}
    where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
),

keyed as (
    select
        *,
        replace(lower(full_name), ' ', '') as full_key
    from names
)

select
    cd3_b_id as record_id,
    mecid as mec_committee_id,
    committee_name,
    case
        when
            company_clean is not null
            and replace(lower(company_clean), ' ', '') not in (coalesce(last_key, ''), coalesce(full_key, ''))
            then company_clean
        else coalesce(full_name, company_clean, person_name_any)
    end as payee_name,
    purpose,
    expenditure_type,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ dbt.safe_cast('date_clean', 'date') }} as expenditure_date,
    {{ dbt.safe_cast('year_clean', dbt.type_int()) }} as expenditure_year,
    city_final as payee_city,
    state_norm as payee_state,
    report
from keyed
