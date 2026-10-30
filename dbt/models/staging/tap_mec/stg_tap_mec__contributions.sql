{{ config(materialized='table') }}
-- MEC itemized contributions received by Missouri committees (TAP mirror, 2011-2022).
-- The mirror combines two MEC export layouts; coalesce the overlapping columns. dupe_flag marks rows TAP
-- identified as duplicates (amended reports) and they're dropped.
-- The second layout (2020-2022) has no ctrb_name / ctrb_type: a committee donor is named in `committee`, an
-- organization in `company`, a person in first/last name (blank strings, not nulls, when absent).
-- The placeholder-name rules below live in the shared macros in macros/names.sql (clean_name, name_part,
-- person_name; #127).
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
-- The un-shift signature and the final company fallback use the same clean_name test as the other names (#472): a
-- '~~' / '--' placeholder counts as missing and is never emitted as the donor, and a one-character company no longer
-- types a row Organization. No row of the current TAP files carries a placeholder of two or more characters there, so
-- only 3 one-character-company rows change type (Organization to Individual).
-- Not handled (left as reported): addresses typed into ctrb_name, and surnames repeated in first_name.
-- The model exposes no address columns, so only name and type are repaired.
-- Identity and double loading (#82, #75, #83): record_id is the source row's own id, txn in the older export layout
-- or cd1_a_id in the 2020-2022 layout. The two TAP files overlap for 2020 and share one MEC id space: all 19,231 ids
-- present as both a txn and a cd1_a_id are the same record (same committee, date, amount, address), so the id is
-- not prefixed with its layout. TAP also loaded 97.5k transactions twice (same id, same file; only address_clean
-- differs, because TAP doubled the address), which counted ~$179M twice. One row per record_id is kept, preferring
-- the newer layout (cd1_a_id, no txn) when an id is in both (the shared columns are identical; the older layout's
-- only extras are ctrb_name / ctrb_type), then the copy whose address_clean is not doubled (the shorter one).
-- Cross-layout near-duplicates (#99): 290 person and 107 organization gifts (about $5.2M) appear once in each layout
-- under different ids. Two mechanisms: an amended report re-filed in the 2020-2022 export (older report X against
-- newer "AMENDED X": 267 rows, $0.79M), and a 24-hour notice re-itemized in the next full report (28 rows, $4.19M,
-- about 81% of the dollars, including all four Democratic Governors Association gifts: $3.55M across two
-- committees); the remaining ~100 rows ($0.2M) pair other reports (8-day-before vs 30-day-after / January
-- Quarterly). Same committee, date, amount and donor
-- (first + last name, else company / committee / ctrb_name, upper-cased and trimmed), one older-layout row (txn)
-- against one newer-layout row (cd1_a_id): the older row is dropped. Matching is one-to-one: rows sharing that key
-- are numbered within each layout (by record_id) and the nth older row is dropped only if the newer layout has an
-- nth row, so a donor who gave the same amount twice in a day in ONE layout keeps both gifts, and a pair with a
-- different amount, date, committee or donor is never matched. Only 2 of 397 matched keys are not 1:1 (2 older
-- rows, 1 newer; the extra older row is kept).

-- A table, not a view like the other staging models: about a dozen models and tests read it, and as a view each
-- re-read the 1.5M Parquet rows and re-ran the name-cleaning regexes (about 10s per full read, under 1s as a table).
{# columns this model reads; unused source columns (zip, address_2, rpt_year, na_flag, zip_clean, filename,
   cd1_a_id after record_id) are not carried through the window sorts (#881) #}
{% set src_cols = [
    'txn', 'cmte_id', 'mecid', 'cmte_name', 'committee_name', 'committee', 'company', 'first_name', 'last_name',
    'address_1', 'address_clean', 'city', 'city_clean', 'state', 'state_clean', 'employer', 'occupation', 'date',
    'amount', 'cont_type', 'contribution_type', 'rpt_type', 'report', 'ctrb_name', 'ctrb_type', 'year',
] %}
{% set key_cols = ['match_committee_id', 'match_date', 'match_amount', 'match_donor'] %}

-- Only the ~7% of record_ids that occur more than once are ranked (#881), and only the ~400 keys present in both
-- layouts are matched; every other row passes through untouched, so the wide rows are not sorted.
with

identified as (
    select
        {{ src_cols | join(', ') }},
        cast(coalesce(txn, cd1_a_id) as {{ dbt.type_string() }}) as record_id
    from {{ source('tap_mec', 'contributions') }}
    where coalesce(dupe_flag, 'FALSE') <> 'TRUE'
),

repeated_ids as (
    select record_id
    from identified
    group by record_id
    having count(*) > 1
),

unique_records as (
    select
        {% for c in src_cols %}i.{{ c }},
        {% endfor %}i.record_id
    from identified as i
    left join repeated_ids as r on i.record_id = r.record_id
    where r.record_id is null

    union all

    select
        {{ src_cols | join(', ') }},
        record_id
    from (
        select
            {% for c in src_cols %}i.{{ c }},
            {% endfor %}i.record_id,
            row_number() over (
                partition by i.record_id
                order by
                    case when i.txn is null then 0 else 1 end,
                    coalesce(length(i.address_clean), 0), i.address_clean, i.address_1, i.amount,
                    i.employer, i.occupation, i.city_clean, i.state_clean, i.committee, i.company, i.first_name,
                    i.last_name, i.ctrb_name, i.ctrb_type, i.date, i.cmte_id, i.mecid,
                    -- every remaining output column, so two rows that differ at all rank deterministically (#226)
                    i.cmte_name, i.committee_name, i.city, i.state, i.cont_type, i.contribution_type, i.rpt_type,
                    i.report, i.year
            ) as record_rank
        from identified as i
        inner join repeated_ids as r on i.record_id = r.record_id
    ) as ranked
    where record_rank = 1
),

layout_keyed as (
    select
        *,
        coalesce(cmte_id, mecid) as match_committee_id,
        {{ dbt.safe_cast('date', 'date') }} as match_date,
        {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as match_amount,
        case
            when nullif(trim(first_name), '') is not null and nullif(trim(last_name), '') is not null
                then upper(trim(first_name)) || ' ' || upper(trim(last_name))
            else upper(coalesce(nullif(trim(company), ''), nullif(trim(committee), ''), nullif(trim(ctrb_name), '')))
        end as match_donor,
        txn is null as is_newer_layout
    from unique_records
),

cross_keys as (
    select {{ key_cols | join(', ') }}
    from layout_keyed
    group by {{ key_cols | join(', ') }}
    having count(distinct is_newer_layout) = 2
),

layout_ranked as (
    select
        k.*,
        row_number() over (
            partition by
                k.match_committee_id, k.match_date, k.match_amount, k.match_donor, k.is_newer_layout
            order by k.record_id
        ) as layout_match_rank
    from layout_keyed as k
    inner join cross_keys as x
        on
            k.match_committee_id = x.match_committee_id
            and k.match_date = x.match_date
            and k.match_amount = x.match_amount
            and k.match_donor = x.match_donor
),

cross_layout_unique as (
    select
        {% for c in src_cols %}k.{{ c }},
        {% endfor %}k.record_id
    from layout_keyed as k
    where
        not exists (
            select 1
            from cross_keys as x
            where
                k.match_committee_id = x.match_committee_id
                and k.match_date = x.match_date
                and k.match_amount = x.match_amount
                and k.match_donor = x.match_donor
        )

    union all

    select
        {% for c in src_cols %}older.{{ c }},
        {% endfor %}older.record_id
    from layout_ranked as older
    where
        older.is_newer_layout
        or not exists (
            select 1
            from layout_ranked as newer
            where
                newer.is_newer_layout
                and newer.match_committee_id = older.match_committee_id
                and newer.match_date = older.match_date
                and newer.match_amount = older.match_amount
                and newer.match_donor = older.match_donor
                and newer.layout_match_rank = older.layout_match_rank
        )
),

source_rows as (
    select
        *,
        {{ mogov.clean_name('ctrb_name') }} as ctrb_name_clean,
        {{ mogov.clean_name('committee') }} as committee_clean,
        {{ mogov.clean_name('company') }} as company_clean,
        coalesce({{ mogov.regex_matches('trim(first_name)', '^[0-9]+$') }}, false) as is_shifted,
        -- rules 2-4 use anchored '^...$' patterns and rule 1 uses '.*x.*'; both mean the same whether the
        -- backend's regex match is anchored or a substring search (#69)
        coalesce(
            {{ mogov.regex_matches('trim(first_name)', '^[0-9]+$') }}
            and {{ mogov.regex_matches('last_name', '.*[A-Za-z].*') }}
            and not {{ mogov.regex_matches('trim(last_name)', '^[0-9]+$') }}
            and {{ mogov.regex_matches('address_1', '.*[A-Za-z].*') }}
            and not {{ mogov.regex_matches('address_1', '.*[0-9].*') }}
            and {{ mogov.clean_name('ctrb_name') }} is null
            and {{ mogov.clean_name('committee') }} is null
            and {{ mogov.clean_name('company') }} is null,
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
            and {{ mogov.clean_name('ctrb_name') }} is null
            and {{ mogov.clean_name('company') }} is null
            and nullif(trim(last_name), '') is null
            and {{ mogov.regex_matches('trim(first_name)', '^.*[A-Za-z].* .*[A-Za-z].*$') }},
            false
        ) as is_org_in_first_name,
        {{ mogov.person_name('first_name', 'last_name') }} as person_name,
        coalesce(cmte_name, committee_name) as recipient_name,
        case
            when
                ctrb_type = 'Individual'
                and {{ mogov.regex_matches('trim(ctrb_name)', '^.* 0$') }}
                and {{ mogov.regex_matches('trim(last_name)', '^.* 0$') }}
                then trim(substring(trim(ctrb_name), 1, length(trim(ctrb_name)) - 2))
        end as ctrb_name_without_zero
    from cross_layout_unique
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
        -- 2020-2022 layout: a filled company is the donor and the name its contact person (#485)
        case
            when
                ctrb_type is null
                then {{ mogov.donor_company('company', 'first_name', 'last_name', 'recipient_name') }}
        end,
        person_name,
        company_clean
    ) as contributor_name,
    case
        when is_id_shifted_person or is_zero_last_person then 'Individual'
        when is_org_in_first_name then ctrb_type
        when ctrb_name is not null and ctrb_name_clean is null and person_name is not null then 'Individual'
        else coalesce(
            ctrb_type,
            case
                when committee_clean is not null then 'Committee'
                -- a filled company is the donor unless it only repeats the person or the recipient (#485)
                when {{ mogov.donor_company('company', 'first_name', 'last_name', 'recipient_name') }} is not null
                    then 'Organization'
                else 'Individual'
            end
        )
    end as contributor_type,
    -- the donor committee's name as reported (no MECID: mec_committee_id is the receiving committee's)
    case
        when ctrb_type = 'Committee' then ctrb_name_clean
        when ctrb_type is null then committee_clean
    end as contributor_committee_name,
    -- 2020-2022 layout only: a company that repeats the person or the recipient is not a business (#485)
    case
        when ctrb_type is null then {{ mogov.donor_company('company', 'first_name', 'last_name', 'recipient_name') }}
        else company
    end as contributor_company,
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
