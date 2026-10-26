-- Sanity check: the Revisor's history/repeal notes fit the parse bounds of int_mo_revisor__session_law_bills
-- (macros/session_law_bounds.sql). split_part_at silently drops parts past its maximum, and notes list acts oldest
-- first, so an exceeded bound would lose the newest acts (a 43-act note once lost 3 of them under a bound of 40).
-- Raise the bound (cheap) when this fails. Counts are upper bounds: commas + 1 acts per note, "merged with" and "&"
-- separators (" & " and " and ") + 1 per act.
{% set bounds = mogov.session_law_bounds() %}
with notes as (
    select
        section_version_id,
        {{ mogov.normalize_session_law_note('history_note') }} as note
    from {{ ref('stg_mo_revisor__sections') }}
    where history_note is not null

    union all

    select
        section_version_id,
        {{ mogov.normalize_session_law_note('note') }} as note
    from {{ ref('stg_mo_revisor__repeals') }}
    where change_kind = 'repealed'
),

spine as (
    select cast(generated_number as {{ dbt.type_int() }}) as n
    from ({{ dbt_utils.generate_series(bounds.max_acts) }}) as s
),

acts as (
    select
        n.section_version_id,
        n.note,
        trim({{ mogov.split_part_at('n.note', "', '", 's.n', bounds.max_acts) }}) as act
    from notes as n
    cross join spine as s
    where s.n <= {{ dbt.length('n.note') }} - {{ dbt.length(dbt.replace('n.note', "','", "''")) }} + 1
)

select
    'acts in one note' as what,
    section_version_id,
    {{ dbt.length('note') }} - {{ dbt.length(dbt.replace('note', "','", "''")) }} + 1 as n
from notes
where {{ dbt.length('note') }} - {{ dbt.length(dbt.replace('note', "','", "''")) }} + 1 > {{ bounds.max_acts }}

union all

select
    'bills merged with in one act' as what,
    section_version_id,
    ({{ dbt.length('act') }} - {{ dbt.length(dbt.replace('act', "' merged with '", "''")) }})
    / {{ dbt.length("' merged with '") }} + 1 as n
from acts
where
    ({{ dbt.length('act') }} - {{ dbt.length(dbt.replace('act', "' merged with '", "''")) }})
    / {{ dbt.length("' merged with '") }} + 1 > {{ bounds.max_merged }}

union all

select
    'bills joined by & or and in one act' as what,
    section_version_id,
    ({{ dbt.length('act') }} - {{ dbt.length(dbt.replace('act', "' & '", "''")) }})
    / {{ dbt.length("' & '") }}
    + ({{ dbt.length('act') }} - {{ dbt.length(dbt.replace('act', "' and '", "''")) }})
    / {{ dbt.length("' and '") }}
    + 1 as n
from acts
where
    ({{ dbt.length('act') }} - {{ dbt.length(dbt.replace('act', "' & '", "''")) }})
    / {{ dbt.length("' & '") }}
    + ({{ dbt.length('act') }} - {{ dbt.length(dbt.replace('act', "' and '", "''")) }})
    / {{ dbt.length("' and '") }}
    + 1 > {{ bounds.max_combined }}
