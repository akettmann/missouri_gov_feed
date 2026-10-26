-- fct_jurisdiction_businesses.donor_links is a text format: lines of `https://<url> <donor name>` joined by a
-- newline. A donor name holding a CR/LF would split a line and hand the frontend a broken link, so every line
-- must start with https://, no line may be empty or end in a space, and each must have a space (the url/name
-- split). Done with length arithmetic instead of a regex so it runs on any dbt backend (#268).
with checked as (
    select
        registry_id,
        official_id,
        donor_links,
        {{ dbt.length('donor_links') }}
        - {{ dbt.length("replace(donor_links, " ~ mogov.chr(10) ~ ", '')") }}
        + 1 as n_lines,
        (
            {{ dbt.length(mogov.chr(10) ~ " || donor_links") }}
            - {{ dbt.length("replace(" ~ mogov.chr(10) ~ " || donor_links, " ~ mogov.chr(10) ~ " || 'https://', '')") }}
        ) / {{ dbt.length(mogov.chr(10) ~ " || 'https://'") }} as n_https_lines,
        {{ dbt.length('donor_links') }} - {{ dbt.length("replace(donor_links, ' ', '')") }} as n_spaces
    from {{ ref('fct_jurisdiction_businesses') }}
    where donor_links is not null
)

select
    official_id,
    registry_id,
    donor_links
from checked
where
    n_lines <> n_https_lines
    or n_spaces < n_lines
    or donor_links like '%' || {{ mogov.chr(13) }} || '%'
    or donor_links like '% '
    or donor_links like '% ' || {{ mogov.chr(10) }} || '%'
