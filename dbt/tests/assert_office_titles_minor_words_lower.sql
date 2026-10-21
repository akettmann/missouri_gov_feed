-- Sanity check: office titles keep short connecting words lower case ("Mayor of Saint Louis", not "Mayor Of
-- Saint Louis"). Title-casing a whole assembled title capitalizes them; title-case its parts instead.
select
    official_id,
    office,
    office_title
from {{ ref('int_officials__current') }}
where
    office_title like '% Of %'
    or office_title like '% And %'
    or office_title like '% The %'
    or office_title like '% For %'
