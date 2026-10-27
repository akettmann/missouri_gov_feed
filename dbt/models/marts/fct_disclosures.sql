-- Mandatory (forced-by-office) financial disclosures, one row per disclosed item.
--   U.S. House members   House Clerk annual reports + periodic transaction reports (PDF text, by schedule)
--   U.S. Senators        Senate eFD annual reports + PTRs (structured tables)
--   Federal judges       AO-10 reports via CourtListener (structured, mostly 2020 and earlier)
-- Missouri state officials' and state judges' personal financial disclosure statements are not online
-- (MEC / Supreme Court clerk release them on Sunshine Law request); see official_profile coverage.
-- is_garbled marks AO-10 items whose OCR text is unreadable. They stay here (the item was disclosed and counts
-- toward the report) but are kept out of fct_commercial_ties and fct_family_ties.
-- Amended filings sit beside their originals (Senate "(amendment N)", House "amended report", AO-10 duplicate
-- "_1.pdf"), so counting or summing items across a filer's reports over-counts. is_latest_version marks the
-- newest version of each report (see the `reports` CTE for what "same report" means); filter on it for any
-- count or sum, and leave it off when listing filings.
-- Grain: (official_id, disclosure_item_id), the source item's own identity (House: filing + PDF page + line;
-- Senate: eFD table row; AO-10: CourtListener table + row id). Identical-looking items (the same asset listed
-- twice on one report) are distinct source rows.
with house_members as (
    select
        o.official_id,
        f.doc_id,
        f.filing_year,
        f.filing_kind,
        f.filing_type,
        f.filing_date,
        f.document_url,
        pc.period_end
    from {{ ref('dim_official') }} as o
    inner join {{ ref('stg_house_fd__filings') }} as f
        on
            o.office = 'us_house'
            and f.state_district = 'MO' || {{ mogov.zero_pad('o.district', 2) }}
            and {{ mogov.name_key('f.last_name') }} = {{ mogov.name_key('o.family_name') }}
    left join {{ ref('int_house_fd__period_covered') }} as pc on f.doc_id = pc.doc_id
),

-- Which report a House "amended report" amends. The Clerk index carries no link, so the amendment is taken to
-- amend the most recent annual, candidate or termination report the same filer filed that year on or before the
-- amendment's date. Index type H counts as an annual report here: on the Clerk index it is very likely a new
-- member's first annual report (only 3 of 346 H filings have an O the same year, 233 have an extension X, and
-- the counts follow the freshman classes), so it is a base of the same tier as O. Other index kinds are no base:
-- a periodic transaction report is its own filing; the rest of "other" (withdrawals, B, E, G) holds no report to
-- restate. When the amendment's PDF has a "Period Covered:" line (candidate reports and their amendments carry
-- it; annual and termination reports do not), a base covering through the same last day wins over a later one,
-- and an annual report is the last resort. amends_url is the url of a candidate or
-- termination base, or null when the base is an annual report (or none is on file, the long-standing default).
house_amendment_base as (
    select
        a.official_id,
        a.doc_id,
        b.document_url as base_url,
        b.filing_kind as base_kind,
        row_number() over (
            partition by a.official_id, a.doc_id
            order by
                case
                    when b.period_end = a.period_end then 2
                    when a.period_end is not null and (b.filing_kind = 'annual report' or b.filing_type = 'H') then 0
                    else 1
                end desc,
                b.filing_date desc,
                b.doc_id desc
        ) as base_rank
    from house_members as a
    left join house_members as b
        on
            a.official_id = b.official_id
            and a.filing_year = b.filing_year
            and (b.filing_kind in ('annual report', 'candidate report', 'termination report') or b.filing_type = 'H')
            and a.filing_date >= b.filing_date
    where a.filing_kind = 'amended report'
),

house_amends as (
    select
        official_id,
        doc_id,
        case when base_kind in ('candidate report', 'termination report') then base_url end as amends_url
    from house_amendment_base
    where base_rank = 1
),

house as (
    select
        h.official_id,
        'U.S. House financial disclosure' as disclosure_type,
        h.filing_kind,
        h.filing_year as report_year,
        h.filing_date,
        l.schedule as section,
        l.owner_code as owner,
        l.amount_range as amount,
        l.line_text as description,
        h.document_url,
        am.amends_url,
        false as is_garbled,
        'house:' || h.doc_id || ':' || cast(l.page as {{ dbt.type_string() }}) || ':'
        || cast(l.line_no as {{ dbt.type_string() }}) as disclosure_item_id
    from house_members as h
    inner join {{ ref('int_house_fd__schedule_lines') }} as l on h.doc_id = l.doc_id
    left join house_amends as am on h.official_id = am.official_id and h.doc_id = am.doc_id
),

house_unparsed as (
    -- filings with no extractable text (scanned paper) or not downloaded: still list them
    select
        h.official_id,
        'U.S. House financial disclosure' as disclosure_type,
        h.filing_kind,
        h.filing_year as report_year,
        h.filing_date,
        'document (not text-extractable; see PDF)' as section,
        cast(null as {{ dbt.type_string() }}) as owner,
        cast(null as {{ dbt.type_string() }}) as amount,
        cast(null as {{ dbt.type_string() }}) as description,
        h.document_url,
        am.amends_url,
        false as is_garbled,
        'house:' || h.doc_id as disclosure_item_id
    from house_members as h
    left join house_amends as am on h.official_id = am.official_id and h.doc_id = am.doc_id
    where h.doc_id not in (select sl.doc_id from {{ ref('int_house_fd__schedule_lines') }} as sl)
),

senate as (
    select
        o.official_id,
        'U.S. Senate financial disclosure' as disclosure_type,
        case
            when lower(s.filing_title) like 'periodic%' then 'periodic transaction report' else lower(s.filing_title)
        end
            as filing_kind,
        {{ dbt.safe_cast(mogov.regex_extract('s.filing_title', '(20[0-9]{2})'), dbt.type_int()) }} as report_year,
        s.submitted_date as filing_date,
        s.section,
        s.owner,
        coalesce(s.amount, s.income_amount) as amount,
        s.description,
        s.document_url,
        cast(null as {{ dbt.type_string() }}) as amends_url,
        false as is_garbled,
        'senate:' || s.row_key as disclosure_item_id
    from {{ ref('dim_official') }} as o
    inner join {{ ref('stg_senate_efd__items') }} as s
        on
            o.office = 'us_senate'
            and {{ mogov.name_key('s.last_name') }} = {{ mogov.name_key('o.family_name') }}
),

judges as (
    select
        o.official_id,
        'Federal judicial financial disclosure (AO-10)' as disclosure_type,
        'annual report' as filing_kind,
        i.report_year,
        cast(null as date) as filing_date,
        i.item_kind as section,
        cast(null as {{ dbt.type_string() }}) as owner,
        i.amount_code as amount,
        i.description,
        i.document_url,
        cast(null as {{ dbt.type_string() }}) as amends_url,
        i.is_garbled,
        'courtlistener:' || i.item_id as disclosure_item_id
    from {{ ref('int_judges__federal') }} as o
    inner join {{ ref('stg_fjc__appointments') }} as a on o.fjc_nid = a.fjc_nid and a.appointment_number = 1
    inner join {{ ref('int_courtlistener__judge_disclosure_items') }} as i on a.fjc_jid = i.fjc_id
),

unioned as (
    select * from house
    union all
    select * from house_unparsed
    union all
    select * from senate
    union all
    select * from judges
),

-- One row per filed report (document), with what makes two reports "the same report":
--   report_group    annual reports and their amendments share 'annual report'; every other kind (periodic
--                   transaction report, candidate report, extension request...) is its own group (the
--                   document url), because those are separate filings, not revisions of each other.
--                   A report with no report_year can't be matched to its siblings either (Senate candidate
--                   reports), so it stays its own group.
--                   A House amendment of a candidate or termination report joins that report's group instead
--                   (house_amendment_base); otherwise it would be a second "latest" beside the report it amends
--                   and could supersede an annual report it does not amend.
--   report_version  0 = original, N = amendment N (Senate "(amendment N)"; AO-10 pdf name suffix "_1" = 1;
--                   House "amended report": the clerk index carries no amendment number, so N is the amendment's
--                   position by filing date among the amendments of its report, ties broken by the numeric
--                   doc id in the url, which grows with time)
--   has_text        false for House scans with no extractable text. Such an amendment cannot stand in for a
--                   readable report, so it never supersedes one.
keyed as (
    select
        *,
        case
            when amends_url is not null then amends_url
            when report_year is not null and filing_kind in ('annual report', 'amended report') then 'annual report'
            when report_year is not null and filing_kind like 'annual report for cy%' then 'annual report'
            else document_url
        end as report_group,
        case
            when disclosure_type like 'U.S. Senate%'
                then
                    coalesce(
                        {{ dbt.safe_cast(mogov.regex_extract('filing_kind', 'amendment ([0-9]+)'), dbt.type_int()) }}, 0
                    )
            when disclosure_type like 'U.S. House%'
                then case when filing_kind = 'amended report' then 1 else 0 end
            else
                coalesce(
                    {{ dbt.safe_cast(
                        mogov.regex_extract('lower(document_url)', '_([0-9]+)[.]pdf$'), dbt.type_int()
                    ) }}, 0
                )
        end as report_version
    from unioned
),

document_reports as (
    select
        official_id,
        disclosure_type,
        report_year,
        document_url,
        report_group,
        max(report_version) as report_version,
        max(filing_date) as filing_date,
        min(case when section like 'document (not text-extractable%' then 0 else 1 end) as has_text
    from keyed
    group by official_id, disclosure_type, report_year, document_url, report_group
),

reports as (
    select
        official_id,
        disclosure_type,
        report_year,
        document_url,
        report_group,
        case
            when disclosure_type like 'U.S. House%' and report_version > 0
                then
                    cast(row_number() over (
                        partition by official_id, disclosure_type, report_year, report_group, report_version
                        order by
                            filing_date,
                            {{ dbt.safe_cast(
                                mogov.regex_extract('lower(document_url)', '([0-9]+)[.]pdf$'), dbt.type_int()
                            ) }},
                            document_url
                    ) as {{ dbt.type_int() }})
            else report_version
        end as report_version,
        filing_date,
        has_text
    from document_reports
),

ranked as (
    select
        *,
        row_number() over (
            partition by official_id, disclosure_type, report_year, report_group
            order by has_text desc, report_version desc, filing_date desc, document_url desc
        ) = 1 as is_latest_version
    from reports
)

select
    u.official_id,
    u.disclosure_type,
    u.filing_kind,
    u.report_year,
    u.filing_date,
    u.section,
    u.owner,
    u.amount,
    u.description,
    u.document_url,
    u.is_garbled,
    u.disclosure_item_id,
    r.report_version,
    r.is_latest_version
from unioned as u
inner join ranked as r
    on
        u.official_id = r.official_id
        and u.disclosure_type = r.disclosure_type
        and u.document_url = r.document_url
        and u.report_year is not distinct from r.report_year
