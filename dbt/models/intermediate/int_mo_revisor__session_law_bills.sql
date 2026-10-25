-- The bills named in the Revisor's session-law citations: each RSMo section version's history note and each repeal
-- note, split into one row per (section version, act, bill). A history note lists the acts that made the section:
-- "(L. 1945 p. 1428 § 48, A.L. 2003 S.B. 299 & 40)" is enacted in 1945 (session-law page, no bill number) and
-- amended in 2003 by SB 299 and SB 40 (combined); "merged with" joins bills that changed the same section in one
-- session; "1st Ex. Sess." names an extraordinary session. change is enacted (L.), amended (A.L., or "A." in the
-- 1949 revision's notes) or repealed ("Repealed L."). Acts cited by page ("p. 1428") name no bill and are left out.
-- session_code follows the House XML codes: two-digit year, then 1 for the regular session. The House numbers every
-- special session (codes 2-4, in order), but the Revisor counts only extraordinary sessions that passed bills: 2018's
-- legislature-called impeachment session (183, resolutions only) isn't one, so the Revisor's 2018 "1st Ex. Sess." is
-- House 184. So the Nth extraordinary session is the year's Nth special-session code with House bills in the House
-- XML; for years before the export (2017), N + 2 is assumed (2017 and later follow it apart from 2018).
{# act: "Repealed L. 2018 ...", "A.L. 2003 ...", "L. 1945 ...", "A. 1949 ..."; bill: "H.B.", "S.B", "S.J.R.", "SJR" #}
{% set act_head = '^(Repealed )?(A\\.L\\.|L\\.|A\\.) ' %}
{% set bill_head = '^[HS]\\.? ?[BJC]\\.? ?R?\\.?' %}

with notes as (
    select
        section_id,
        section_version_id,
        history_note as note
    from {{ ref('stg_mo_revisor__sections') }}
    where history_note is not null

    union all

    select
        section_id,
        section_version_id,
        note
    from {{ ref('stg_mo_revisor__repeals') }}
    where change_kind = 'repealed'
),

normalized as (
    select
        section_id,
        section_version_id,
        -- one separator between acts; "et al." belongs to the act before it
        replace(replace(replace(replace(note, '(', ''), ')', ''), '; ', ', '), ', et al.', ' et al.') as note
    from notes
),

spine as (
    select cast(generated_number as {{ dbt.type_int() }}) as n
    from ({{ dbt_utils.generate_series(40) }}) as s
),

acts as (
    select
        o.section_id,
        o.section_version_id,
        s.n as act_index,
        trim({{ dbt.split_part('o.note', "', '", 's.n') }}) as act
    from normalized as o
    cross join spine as s
    where s.n <= {{ dbt.length('o.note') }} - {{ dbt.length(dbt.replace('o.note', "','", "''")) }} + 1
),

parsed_acts as (
    select
        section_id,
        section_version_id,
        act_index,
        act,
        case
            when act like 'Repealed %' then 'repealed'
            when act like 'A.L. %' or act like 'A. %' then 'amended'
            else 'enacted'
        end as change,
        {{ dbt.safe_cast(mogov.regex_extract('act', act_head ~ '([0-9]{4})', 3), dbt.type_int()) }} as act_year,
        {{ dbt.safe_cast(mogov.regex_extract('act', '([1-3])(st|nd|rd) Ex\\. Sess\\.', 1), dbt.type_int()) }}
            as extra_session,
        {#- what follows the year (and the session): the bill references #}
        {{ mogov.regex_replace_all(
            mogov.regex_replace_all('act', act_head ~ '[0-9]{4} ', ''), '^[1-3](st|nd|rd) Ex\\. Sess\\. ', ''
        ) }} as refs
    from acts
    where {{ mogov.regex_matches('act', act_head ~ '[0-9]{4}') }}
),

merged as (
    select
        a.section_id,
        a.section_version_id,
        a.act_index,
        a.act,
        a.change,
        a.act_year,
        a.extra_session,
        s.n as ref_index,
        trim({{ dbt.split_part('a.refs', "' merged with '", 's.n') }}) as ref
    from parsed_acts as a
    cross join spine as s
    where
        s.n <= 10
        and {{ dbt.split_part('a.refs', "' merged with '", 's.n') }} <> ''
),

typed as (
    select
        *,
        -- "H.B.", "S.B", "S.J.R.", "SJR" -> HB, SB, SJR
        {{ mogov.regex_replace_all(mogov.regex_extract('ref', '(' ~ bill_head ~ ') ?[0-9]', 1), '[^A-Z]', '') }}
            as bill_type,
        -- "299 & 40 § A Revision" -> "299 & 40"
        {{ mogov.regex_extract('ref', bill_head ~ ' ?([0-9]+( & [0-9]+)*)', 1) }} as numbers
    from merged
),

bills as (
    select
        t.section_id,
        t.section_version_id,
        t.act_index,
        t.act,
        t.change,
        t.act_year,
        t.extra_session,
        t.ref_index,
        t.bill_type,
        trim({{ dbt.split_part('t.numbers', "' & '", 's.n') }}) as bill_number
    from typed as t
    cross join spine as s
    where
        t.bill_type is not null
        and s.n <= 6
        and {{ dbt.split_part('t.numbers', "' & '", 's.n') }} <> ''
),

extra_sessions as (
    select
        session_year,
        session_code,
        row_number() over (partition by session_year order by session_code) as ordinal
    from (
        select distinct
            session_year,
            session_code
        from {{ ref('stg_mo_house__bills') }}
        where right(session_code, 1) <> '1' and bill like 'HB%'
    ) as codes
)

select distinct
    b.section_id,
    b.section_version_id,
    b.change,
    b.act_year,
    b.extra_session,
    case
        when b.extra_session is null
            then {{ dbt.right(dbt.safe_cast('b.act_year', dbt.type_string()), 2) }} || '1'
        else coalesce(
            x.session_code,
            {{ dbt.right(dbt.safe_cast('b.act_year', dbt.type_string()), 2) }}
            || {{ dbt.safe_cast('b.extra_session + 2', dbt.type_string()) }}
        )
    end as session_code,
    b.bill_type || b.bill_number as bill,
    b.act
from bills as b
left join extra_sessions as x on b.act_year = x.session_year and b.extra_session = x.ordinal
