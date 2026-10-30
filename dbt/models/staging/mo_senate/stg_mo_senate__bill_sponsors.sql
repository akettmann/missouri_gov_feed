-- The primary sponsor of each Senate bill or resolution (SB, SJR, SCR, SR) as senate.mo.gov's bill list gives him or
-- her, shaped like stg_mo_house__bill_sponsors (the list has no co-sponsors, handlers or conferees, so sponsor_type
-- is always 'Sponsor'). session_code is the House's code for the session (seed mo_senate_session_codes), null for a
-- session with no seed row. sponsor_name is "First Last". The list prints a surname shared by two senators with the
-- district after it ("Brown (16)"); that suffix is dropped from the name, and the district column keeps it apart.
-- sponsor_district is the senate district itself (the House XML numbers senators 200 + district; this list does not).
-- A bill the list gives no sponsor (2022 SB 2162 has none) is left out.
with src as (
    select
        {{ dbt.safe_cast(
            "coalesce(" ~ mogov.json_str('payload', '$.list_year') ~ ", " ~ mogov.json_str('payload', '$.year') ~ ")",
            dbt.type_int()
        ) }} as session_year,
        {{ mogov.json_str('payload', '$.session_type') }} as session_type,
        {{ mogov.json_str('payload', '$.billPrefix') }} as bill_type,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.billSuffix'), dbt.type_int()) }} as bill_number,
        {{ mogov.json_str('payload', '$.sponsorFirstName') }} as sponsor_first_name,
        {{ mogov.regex_replace_all(mogov.json_str('payload', '$.sponsorLastName'), '\\s*\\([0-9]+\\)\\s*$', '') }}
            as sponsor_last_name,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.legislatorId'), dbt.type_int()) }} as legislator_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.districtNumber'), dbt.type_int()) }} as sponsor_district
    from {{ source('mo_senate', 'bill_list') }}
),

named as (
    select
        *,
        {{ mogov.person_name('sponsor_first_name', 'sponsor_last_name') }} as sponsor_name
    from src
)

select
    codes.house_session_code as session_code,
    named.session_year,
    named.session_type,
    named.bill_type || cast(named.bill_number as {{ dbt.type_string() }}) as bill,
    'Sponsor' as sponsor_type,
    named.sponsor_name,
    named.legislator_id,
    named.sponsor_district
from named
left join {{ ref('mo_senate_session_codes') }} as codes
    on named.session_year = codes.session_year and named.session_type = codes.session_type
where named.sponsor_name is not null
