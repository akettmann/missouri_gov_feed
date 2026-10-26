{{ config(enabled=var('mec_direct', false)) }}
-- MEC itemized contributions received (direct export, recent report years). Dates "M/D/YYYY 12:00:00 AM".
select
    mecid as mec_committee_id,
    committee_name,
    coalesce(
        nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''), company, committee
    ) as contributor_name,
    case
        when committee is not null and committee <> '' then 'Committee'
        -- a company beside a person's name is the person's employer, not the donor (#485)
        when company is not null and company <> '' and not {{ mogov.has_person_name('first_name', 'last_name') }}
            then 'Organization'
        else 'Individual'
    end as contributor_type,
    -- the donor committee's name as reported (no MECID: mecid is the receiving committee's)
    nullif(trim(committee), '') as contributor_committee_name,
    coalesce(
        nullif({{ mogov.company_unless_person_name('company', 'first_name', 'last_name') }}, ''), nullif(committee, '')
    ) as contributor_company,
    employer as contributor_employer,
    occupation as contributor_occupation,
    trim(city) as contributor_city,
    state as contributor_state,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ mogov.parse_date(dbt.split_part('date', "' '", 1), '%m/%d/%Y') }} as contribution_date,
    cast(
        extract(year from {{ mogov.parse_date(dbt.split_part('date', "' '", 1), '%m/%d/%Y') }})
        as {{ dbt.type_int() }}
    ) as contribution_year,
    contribution_type as contribution_kind,
    report,
    cd1_a_id as record_id
from {{ source('mec', 'cd1_a') }}
