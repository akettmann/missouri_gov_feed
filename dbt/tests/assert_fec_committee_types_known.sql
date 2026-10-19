-- FEC committee type codes in the committee master that the fec_committee_types seed can't decode.
-- Warns rather than fails: a new FEC code only leaves that label raw until the seed is updated.
{{ config(severity='warn') }}
select distinct c.committee_type
from {{ ref('stg_fec__committees') }} as c
left join {{ ref('fec_committee_types') }} as t on c.committee_type = t.code
where c.committee_type is not null and t.code is null
