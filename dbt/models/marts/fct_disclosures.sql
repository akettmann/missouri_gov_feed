-- Mandatory (forced-by-office) financial disclosures, one row per disclosed item.
--   U.S. House members   House Clerk annual reports + periodic transaction reports (PDF text, by schedule)
--   U.S. Senators        Senate eFD annual reports + PTRs (structured tables)
--   Federal judges       AO-10 reports via CourtListener (structured, mostly 2020 and earlier)
-- Missouri state officials' and state judges' personal financial disclosure statements are not online
-- (MEC / Supreme Court clerk release them on Sunshine Law request); see official_profile coverage.
-- is_garbled marks AO-10 items whose OCR text is unreadable. They stay here (the item was disclosed and counts
-- toward the report) but are kept out of fct_commercial_ties and fct_family_ties.
-- Grain: (official_id, disclosure_item_id), the source item's own identity (House: filing + PDF page + line;
-- Senate: eFD table row; AO-10: CourtListener table + row id). Identical-looking items (the same asset listed
-- twice on one report) are distinct source rows.
with house_members as (
    select
        o.official_id,
        f.doc_id,
        f.filing_year,
        f.filing_kind,
        f.filing_date,
        f.document_url
    from {{ ref('dim_official') }} as o
    inner join {{ ref('stg_house_fd__filings') }} as f
        on
            o.office = 'us_house'
            and f.state_district = 'MO' || {{ mogov.zero_pad('o.district', 2) }}
            and {{ mogov.name_key('f.last_name') }} = {{ mogov.name_key('o.family_name') }}
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
        false as is_garbled,
        'house:' || h.doc_id || ':' || cast(l.page as {{ dbt.type_string() }}) || ':'
        || cast(l.line_no as {{ dbt.type_string() }}) as disclosure_item_id
    from house_members as h
    inner join {{ ref('int_house_fd__schedule_lines') }} as l on h.doc_id = l.doc_id
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
        false as is_garbled,
        'house:' || h.doc_id as disclosure_item_id
    from house_members as h
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
        i.is_garbled,
        'courtlistener:' || i.item_id as disclosure_item_id
    from {{ ref('int_judges__federal') }} as o
    inner join {{ ref('stg_fjc__appointments') }} as a on o.fjc_nid = a.fjc_nid and a.appointment_number = 1
    inner join {{ ref('int_courtlistener__judge_disclosure_items') }} as i on a.fjc_jid = i.fjc_id
)

select * from house
union all
select * from house_unparsed
union all
select * from senate
union all
select * from judges
