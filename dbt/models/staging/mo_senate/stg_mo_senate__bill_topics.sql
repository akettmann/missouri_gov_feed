-- Subject keywords per bill from the MO Senate topical index (regular sessions): Senate bills and the House
-- bills that reached the Senate. subject_name is the keyword upper-cased into the House index's spelling;
-- the two indexes share their terms except "..., DEPARTMENT OF" (House "DEPT. OF") and "WORKERS'
-- COMPENSATION" (House drops the apostrophe). session_code follows the House codes (two-digit year + 1).
with src as (
    select
        {{ dbt.safe_cast(mogov.json_str('payload', '$.year'), dbt.type_int()) }} as session_year,
        {{ mogov.json_str('payload', '$.keyword') }} as keyword,
        {{ mogov.json_str('payload', '$.bill_label') }} as bill_label,
        {{ mogov.json_str('payload', '$.bill_url') }} as bill_url,
        {{ mogov.json_str('payload', '$.description') }} as description,
        {{ mogov.json_str('payload', '$.sponsors[0].name') }} as sponsor_name,
        source_url
    from {{ source('mo_senate', 'bill_topics') }}
)

select
    session_year,
    {{ dbt.right(dbt.safe_cast('session_year', dbt.type_string()), 2) }} || '1' as session_code,
    replace(bill_label, ' ', '') as bill,
    bill_label,
    keyword,
    case upper(keyword)
        when 'ELEMENTARY AND SECONDARY EDUCATION, DEPARTMENT OF' then 'ELEMENTARY AND SECONDARY EDUCATION, DEPT. OF'
        when 'WORKERS'' COMPENSATION' then 'WORKERS COMPENSATION'
        else upper(keyword)
    end as subject_name,
    description,
    sponsor_name,
    bill_url,
    source_url
from src
