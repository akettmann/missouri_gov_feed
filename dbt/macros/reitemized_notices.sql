{#- Contributions with the 24-hour notices that a later full report itemizes again removed (#156, #542).
    A gift of $5,000+ is first reported on a "24 Hour ..." notice and then listed again, as a line of its own, in the
    committee's next full report (8 Day Before, 30 Day After, Quarterly, ...). Both lines carry the same committee, date
    and amount, and the full report's line covers the gift's date, so the notice line is dropped. Two matching tiers:

    1. Same donor. Rows sharing a key (committee, date, amount, donor) are numbered separately among the notices and
       among the full-report lines (by record_id), and the nth notice is dropped only if the nth full-report line
       exists, so a donor who gave the same amount twice in a day keeps both gifts when both appear in full reports and
       a notice with no matching full-report line (no later report, a different amount, date or donor) is kept. The
       donor is compared by name_key (case, punctuation and runs of spaces ignored).
    2. Same donor, spelled differently (#542). Among the lines tier 1 left over, a committee, date and amount with
       exactly ONE leftover notice and exactly ONE leftover full-report line (a donor-less line counts, so it blocks the
       match) is a pair when both lines name the same city and state and the donor names are loose_name_key twins, or
       within a couple of letters of each other (typos: "Lathrop GPM" / "Lanthrop GPM") on names of 10+ characters
       with the same digits ("LIUNA Local 110 PAC Fund" is not "LIUNA Local 100 PAC Fund"). With two or more leftover
       lines on either side it is unknowable who gave what, so every notice is kept.

    Rows missing a committee, date, amount or donor are never matched in tier 1, and a row without a city and state
    never in tier 2. rel is a relation with record_id, mec_committee_id, contributor_name, contributor_city,
    contributor_state, amount, contribution_date and report.
    Applies to both MEC feeds: the TAP mirror and the direct export. -#}

{#- A donor name as a looser match key than name_key: "MO"/"Missouri" alike, stop words ("and", "of", "the"), legal-form
    words ("LLC", "Inc") and single letters (middle initials) dropped. "James B Nutter" and "James Nutter" give
    "james nutter"; "Democratic Federal Campaign Committee of St. Louis City PAC" and the same without "of" are equal.
    The padding spaces let each word be matched whole; the pass runs twice because adjacent words share a space. -#}
{% macro loose_name_key(expr) -%}
    {%- set words = " (and|of|the|inc|incorporated|llc|co|corp|company|ltd|[a-z]) " -%}
    {%- set padded = "replace(' ' || " ~ mogov.name_key(expr) ~ " || ' ', ' mo ', ' missouri ')" -%}
    trim({{ mogov.regex_replace_all(
        mogov.regex_replace_all(mogov.regex_replace_all(padded, words, ' '), words, ' '),
        ' +', ' '
    ) }})
{%- endmacro %}

{% macro drop_reitemized_notices(rel) -%}
with

keyed as (
    select
        record_id,
        upper(trim(mec_committee_id)) as match_committee_id,
        contribution_date as match_date,
        amount as match_amount,
        nullif({{ mogov.name_key('contributor_name') }}, '') as match_donor,
        nullif(upper(trim(contributor_city)), '') as match_city,
        nullif(upper(trim(contributor_state)), '') as match_state,
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

exact_pairs as (
    select
        notice.record_id as notice_id,
        full_report.record_id as full_report_id
    from ranked as notice
    inner join ranked as full_report
        on
            notice.match_committee_id = full_report.match_committee_id
            and notice.match_date = full_report.match_date
            and notice.match_amount = full_report.match_amount
            and notice.match_donor = full_report.match_donor
            and notice.match_rank = full_report.match_rank
    where notice.is_notice and not full_report.is_notice
),

leftover as (
    select
        *,
        sum(case when is_notice then 1 else 0 end) over (
            partition by match_committee_id, match_date, match_amount
        ) as notices_left,
        sum(case when is_notice then 0 else 1 end) over (
            partition by match_committee_id, match_date, match_amount
        ) as full_reports_left
    from keyed
    where
        record_id not in (select notice_id from exact_pairs)
        and record_id not in (select full_report_id from exact_pairs)
),

similar_pairs as (
    select
        notice.record_id as notice_id,
        notice.match_donor as notice_donor,
        {{ mogov.loose_name_key('notice.match_donor') }} as notice_loose,
        {{ mogov.loose_name_key('full_report.match_donor') }} as full_report_loose,
        full_report.match_donor as full_report_donor
    from leftover as notice
    inner join leftover as full_report
        on
            notice.match_committee_id = full_report.match_committee_id
            and notice.match_date = full_report.match_date
            and notice.match_amount = full_report.match_amount
            and notice.match_city = full_report.match_city
            and notice.match_state = full_report.match_state
    where
        notice.is_notice
        and not full_report.is_notice
        and notice.notices_left = 1
        and notice.full_reports_left = 1
        and notice.match_donor is not null
        and full_report.match_donor is not null
),

reitemized as (
    select notice_id as record_id from exact_pairs
    union
    select notice_id
    from similar_pairs
    where
        notice_loose = full_report_loose
        or (
            length(notice_loose) >= 10
            and length(full_report_loose) >= 10
            and {{ mogov.regex_replace_all('notice_loose', '[^0-9]', '') }}
            = {{ mogov.regex_replace_all('full_report_loose', '[^0-9]', '') }}
            and {{ mogov.edit_distance('notice_loose', 'full_report_loose') }} <= 2
            and 10 * {{ mogov.edit_distance('notice_loose', 'full_report_loose') }}
            <= greatest(length(notice_loose), length(full_report_loose))
        )
)

select c.*
from {{ rel }} as c
where not exists (select 1 from reitemized as r where r.record_id = c.record_id)
{%- endmacro %}
