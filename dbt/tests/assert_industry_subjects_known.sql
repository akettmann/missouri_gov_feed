-- industry_subjects terms that no bill in fct_bill_subjects carries (the House renamed or dropped an index term).
-- Warns rather than fails: such a term only stops linking bills to that industry until the seed is updated.
{{ config(severity='warn') }}
select distinct i.subject_name
from {{ ref('industry_subjects') }} as i
left join {{ ref('fct_bill_subjects') }} as s on i.subject_name = s.subject_name
where s.subject_name is null
