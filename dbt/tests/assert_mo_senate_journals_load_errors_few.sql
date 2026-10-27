-- A Senate journal PDF the loader could not fetch or extract (fetch error, extraction timeout) lands as an error row
-- in mo_senate_journals with no vote rows, and nothing downstream stages that table, so a journal that fails on
-- every run would go unnoticed and its roll calls would be missing. A few are a flaky day (the next run retries
-- them); more than 5 journals means the site changed or the extractor times out on everything. Warns (#714).
{{ config(severity='warn') }}

select count(distinct {{ mogov.json_str('payload', '$.url') }}) as journals_with_load_errors
from {{ source('mo_senate', 'journals') }}
where {{ mogov.json_str('payload', '$.error') }} is not null
having count(distinct {{ mogov.json_str('payload', '$.url') }}) > 5
