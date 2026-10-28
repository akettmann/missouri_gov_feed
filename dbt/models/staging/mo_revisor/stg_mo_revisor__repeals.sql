-- One row per repealed or transferred RSMo section (the Revisor's repeals-and-transfers list). note is as printed:
-- "(Repealed L. 1975 H.B. 945 § 1)", "(Transferred 2013; now 29.351)" or "(Transferred 1978 to 565.004; repealed
-- 1983)"; transferred_to is the section it moved to. action_date is the date the repeal or transfer took effect;
-- the Revisor dates a repeal that waits on a contingency 1 Jan 2099, which becomes is_contingent with no date. The
-- list also carries repealed constitution sections ("V Section 25"); they are left out here. fetched_at is when
-- the list page (one page for every row) was fetched from revisor.mo.gov, null on rows loaded before the loader
-- recorded it (#852). loaded_at is when our pipeline last published the raw table, up to 7 days after the fetch.
with src as (
    select
        {{ mogov.json_str('payload', '$.section') }} as section_id,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.bid'), dbt.type_int()) }} as bid,
        {{ mogov.json_str('payload', '$.kind') }} as change_kind,
        {{ mogov.json_str('payload', '$.note') }} as note,
        {{ mogov.parse_date(mogov.json_str('payload', '$.date'), '%m/%d/%Y') }} as printed_date,
        {{ dbt.safe_cast(mogov.json_str('payload', '$.fetched_at'), 'timestamp with time zone') }} as fetched_at,
        source_url,
        loaded_at
    from {{ source('mo_revisor', 'repeals') }}
)

select
    section_id,
    bid,
    section_id || '/' || {{ dbt.safe_cast('bid', dbt.type_string()) }} as section_version_id,
    {{ dbt.split_part('section_id', "'.'", 1) }} as chapter,
    change_kind,
    note,
    case when printed_date < cast('2099-01-01' as date) then printed_date end as action_date,
    coalesce(printed_date >= cast('2099-01-01' as date), false) as is_contingent,
    case
        when change_kind = 'transferred'
            then {{ mogov.regex_extract('note', '(now|to) ([0-9]+[A-Z]?\\.[0-9A-Za-z-]+)', 2) }}
    end as transferred_to,
    source_url,
    fetched_at,
    loaded_at
from src
where {{ mogov.regex_matches('section_id', '^[0-9]') }}
