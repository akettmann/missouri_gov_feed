{#- Contributions with the 24-hour notices that a later full report itemizes again removed (#156).
    A gift of $5,000+ is first reported on a "24 Hour ..." notice and then listed again, as a line of its own, in the
    committee's next full report (8 Day Before, 30 Day After, Quarterly, ...). Both lines carry the same committee, date,
    amount and donor, and the full report's line covers the gift's date, so the notice line is dropped. Matching is
    one-to-one: rows sharing a key are numbered separately among the notices and among the full-report lines (by
    record_id), and the nth notice is dropped only if the nth full-report line exists, so a donor who gave the same
    amount twice in a day keeps both gifts when both appear in full reports and a notice with no matching full-report
    line (no later report, a different amount, date or donor) is kept. The donor is compared by name_key (case,
    punctuation and runs of spaces ignored). Rows missing a committee, date, amount or donor are never matched.
    rel is a relation with record_id, mec_committee_id, contributor_name, amount, contribution_date and report.
    Applies to both MEC feeds: the TAP mirror and the direct export. -#}
{% macro drop_reitemized_notices(rel) -%}
with

keyed as (
    select
        record_id,
        upper(trim(mec_committee_id)) as match_committee_id,
        contribution_date as match_date,
        amount as match_amount,
        nullif({{ mogov.name_key('contributor_name') }}, '') as match_donor,
        coalesce(lower(report) like '%24 hour%', false) as is_notice
    from {{ rel }}
    where mec_committee_id is not null and contribution_date is not null and amount is not null
),

ranked as (
    select
        *,
        row_number() over (
            partition by match_committee_id, match_date, match_amount, match_donor, is_notice
            order by record_id
        ) as match_rank
    from keyed
    where match_donor is not null
),

reitemized as (
    select notice.record_id
    from ranked as notice
    where
        notice.is_notice
        and exists (
            select 1
            from ranked as full_report
            where
                not full_report.is_notice
                and full_report.match_committee_id = notice.match_committee_id
                and full_report.match_date = notice.match_date
                and full_report.match_amount = notice.match_amount
                and full_report.match_donor = notice.match_donor
                and full_report.match_rank = notice.match_rank
        )
)

select c.*
from {{ rel }} as c
where not exists (select 1 from reitemized as r where r.record_id = c.record_id)
{%- endmacro %}
