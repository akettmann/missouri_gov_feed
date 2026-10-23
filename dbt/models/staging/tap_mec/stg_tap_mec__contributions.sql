-- MEC itemized contributions received by Missouri committees (TAP mirror, 2011-2022).
-- The mirror combines two MEC export layouts; coalesce the overlapping columns. dupe_flag marks rows TAP
-- identified as duplicates (amended reports) and they're dropped.
-- The second layout (2020-2022) has no ctrb_name / ctrb_type: a committee donor is named in `committee`, an
-- organization in `company`, a person in first/last name (blank strings, not nulls, when absent).
-- Placeholder donor names (#31): ~10k rows carry a one-character ctrb_name / committee ('C', '~', '0', '-', 'x',
-- '_'), almost all with a person's first/last name (federal-committee filings transferred to MEC). A name shorter
-- than 2 characters is treated as missing, so the name falls back to the person's name and the row is typed
-- Individual. With no person's name either, the name stays null and the reported type is kept.
-- The first/last name columns carry the same fillers ('~' / '~', '-' / '-', '?', '.'): a part with no letter or
-- number is dropped before the person's name is built (not "shorter than 2": real initials like 'R' or 'J' stay).
-- Rows whose ctrb_name and both name parts are all '~' / '-' hold the real donor in `company`, so they fall
-- through to it and keep the reported type (Committee) instead of becoming an Individual named '~ ~'.
-- Shifted rows (#60): 3.6k rows of one committee have the columns shifted (first_name holds a numeric record ID,
-- last_name the donor's first name, address_1 the surname). A name part that is all digits is not a name, and
-- when first_name is all digits the remaining parts are shifted too, so no person's name is built from the row:
-- the name stays null (a one-character company is ignored too) and the reported type is kept.
-- Un-shifting (#60), only for rows matching a precise signature (the rest are left as reported):
--   * first_name all digits, last_name a name, address_1 a name, no usable ctrb_name / committee / company
--     (C180576 Enterprise Holdings PAC, 3,619 rows; one C000593 row with a one-digit ID): the person is
--     last_name || ' ' || address_1 (first name, surname), typed Individual.
--   * last_name is the filler '0', first_name a name, address_1 a digit-free name (C000593, 51 rows, ctrb_name
--     'KERRY 0'): the person is first_name || ' ' || address_1, typed Individual.
--   * an Individual ctrb_name 'FIRST LAST 0' whose last_name also ends ' 0' (3 rows): the trailing ' 0' is dropped.
--   * a Corporation whose ctrb_name and company are placeholders, last_name is blank and first_name is a
--     multi-word name (C000642 / C081050, 8 rows): the organization sits in first_name; the name is kept and
--     the reported type stays Corporation rather than becoming Individual.
-- Not handled (left as reported): addresses typed into ctrb_name, and surnames repeated in first_name.
-- The model exposes no address columns, so only name and type are repaired.
-- Identity and double loading (#82, #75, #83): record_id is the source row's own id, txn in the older export layout
-- or cd1_a_id in the 2020-2022 layout. The two TAP files overlap for 2020 and share one MEC id space: all 19,231 ids
-- present as both a txn and a cd1_a_id are the same record (same committee, date, amount, address), so the id is
-- not prefixed with its layout. TAP also loaded 97.5k transactions twice (same id, same file; only address_clean
-- differs, because TAP doubled the address), which counted ~$179M twice. One row per record_id is kept, preferring
-- the newer layout (cd1_a_id, no txn) when an id is in both (the shared columns are identical; the older layout's
-- only extras are ctrb_name / ctrb_type), then the copy whose address_clean is not doubled (the shorter one).
with

identified as (
    select
        *,
        cast(coalesce(txn, cd1_a_id) as {{ dbt.type_string() }}) as record_id
    from {{ source('tap_mec', 'contributions') }}
    where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
),

unique_records as (
    select
        *,
        row_number() over (
            partition by record_id
            order by
                case when txn is null then 0 else 1 end,
                coalesce(length(address_clean), 0), address_clean, address_1, amount
        ) as record_rank
    from identified
),

source_rows as (
    select
        *,
        case
            when length(trim(ctrb_name)) >= 2 and {{ mogov.regex_matches('ctrb_name', '[A-Za-z0-9]') }}
                then trim(ctrb_name)
        end as ctrb_name_clean,
        case
            when length(trim(committee)) >= 2 and {{ mogov.regex_matches('committee', '[A-Za-z0-9]') }}
                then trim(committee)
        end as committee_clean,
        coalesce({{ mogov.regex_matches('trim(first_name)', '^[0-9]+$') }}, false) as is_shifted,
        -- rules 2-4 use anchored '^...$' patterns and rule 1 uses '.*x.*'; both mean the same whether the
        -- backend's regex match is anchored or a substring search (#69)
        coalesce(
            {{ mogov.regex_matches('trim(first_name)', '^[0-9]+$') }}
            and {{ mogov.regex_matches('last_name', '.*[A-Za-z].*') }}
            and not {{ mogov.regex_matches('trim(last_name)', '^[0-9]+$') }}
            and {{ mogov.regex_matches('address_1', '.*[A-Za-z].*') }}
            and not {{ mogov.regex_matches('address_1', '.*[0-9].*') }}
            and coalesce(length(trim(ctrb_name)), 0) < 2
            and coalesce(length(trim(committee)), 0) < 2
            and coalesce(length(trim(company)), 0) < 2,
            false
        ) as is_id_shifted_person,
        coalesce(
            trim(last_name) = '0'
            and {{ mogov.regex_matches('first_name', '.*[A-Za-z].*') }}
            and {{ mogov.regex_matches('address_1', '.*[A-Za-z].*') }}
            and not {{ mogov.regex_matches('address_1', '.*[0-9].*') }}
            and {{ mogov.regex_matches('trim(ctrb_name)', '^.* 0$') }},
            false
        ) as is_zero_last_person,
        coalesce(
            ctrb_type = 'Corporation'
            and ctrb_name is not null
            and (length(trim(ctrb_name)) < 2 or not {{ mogov.regex_matches('ctrb_name', '.*[A-Za-z0-9].*') }})
            and (
                coalesce(length(trim(company)), 0) < 2
                or not coalesce({{ mogov.regex_matches('company', '.*[A-Za-z0-9].*') }}, false)
            )
            and nullif(trim(last_name), '') is null
            and {{ mogov.regex_matches('trim(first_name)', '^.*[A-Za-z].* .*[A-Za-z].*$') }},
            false
        ) as is_org_in_first_name,
        case
            when not coalesce({{ mogov.regex_matches('trim(first_name)', '^[0-9]+$') }}, false)
                then nullif(
                    trim(
                        coalesce(
                            case when {{ mogov.regex_matches('first_name', '[A-Za-z0-9]') }} then trim(first_name) end,
                            ''
                        )
                        || ' '
                        || coalesce(
                            case
                                when
                                    {{ mogov.regex_matches('last_name', '[A-Za-z0-9]') }}
                                    and not {{ mogov.regex_matches('trim(last_name)', '^[0-9]+$') }}
                                    then trim(last_name)
                            end,
                            ''
                        )
                    ),
                    ''
                )
        end as person_name,
        case
            when
                ctrb_type = 'Individual'
                and {{ mogov.regex_matches('trim(ctrb_name)', '^.* 0$') }}
                and {{ mogov.regex_matches('trim(last_name)', '^.* 0$') }}
                then trim(substring(trim(ctrb_name), 1, length(trim(ctrb_name)) - 2))
        end as ctrb_name_without_zero
    from unique_records
    where record_rank = 1
)

select
    record_id,
    coalesce(cmte_id, mecid) as mec_committee_id,
    coalesce(cmte_name, committee_name) as committee_name,
    coalesce(
        case
            when is_id_shifted_person then trim(last_name) || ' ' || trim(address_1)
            when is_zero_last_person then trim(first_name) || ' ' || trim(address_1)
            when is_org_in_first_name then trim(first_name)
        end,
        ctrb_name_without_zero,
        ctrb_name_clean,
        committee_clean,
        person_name,
        case when not is_shifted or length(trim(company)) >= 2 then nullif(trim(company), '') end
    ) as contributor_name,
    case
        when is_id_shifted_person or is_zero_last_person then 'Individual'
        when is_org_in_first_name then ctrb_type
        when ctrb_name is not null and ctrb_name_clean is null and person_name is not null then 'Individual'
        else coalesce(
            ctrb_type,
            case
                when committee_clean is not null then 'Committee'
                when nullif(trim(company), '') is not null then 'Organization'
                else 'Individual'
            end
        )
    end as contributor_type,
    -- the donor committee's name as reported (no MECID: mec_committee_id is the receiving committee's)
    case
        when ctrb_type = 'Committee' then ctrb_name_clean
        when ctrb_type is null then committee_clean
    end as contributor_committee_name,
    company as contributor_company,
    employer as contributor_employer,
    occupation as contributor_occupation,
    coalesce(city_clean, city) as contributor_city,
    coalesce(state_clean, state) as contributor_state,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ dbt.safe_cast('date', 'date') }} as contribution_date,
    {{ dbt.safe_cast('year', dbt.type_int()) }} as contribution_year,
    coalesce(cont_type, contribution_type) as contribution_kind,
    coalesce(rpt_type, report) as report
from source_rows
