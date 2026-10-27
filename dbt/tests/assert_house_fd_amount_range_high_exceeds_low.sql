-- Sanity check on the House disclosure schedule lines: a value range "$low - $high" must run upward. A high end at
-- or below the low end means the parser joined the wrong number to a wrapped range, e.g. the column-header leftover
-- "$1,000?" taken for the high end of "$100,001 -" (#702).
-- Returns the rows whose range has a high end that does not exceed its low end.
with ranges as (
    select
        doc_id,
        page,
        line_no,
        amount_range,
        {{ mogov.regex_extract('amount_range', '^\\$([0-9,]+) - \\$[0-9,]+$') }} as low_text,
        {{ mogov.regex_extract('amount_range', '^\\$[0-9,]+ - \\$([0-9,]+)$') }} as high_text
    from {{ ref('int_house_fd__schedule_lines') }}
    where {{ mogov.regex_matches('amount_range', '^\\$[0-9,]+ - \\$[0-9,]+$') }}
),

parsed as (
    select
        *,
        cast(replace(low_text, ',', '') as bigint) as low_end,
        cast(replace(high_text, ',', '') as bigint) as high_end
    from ranges
)

select *
from parsed
where high_end <= low_end
