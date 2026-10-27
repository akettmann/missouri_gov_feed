-- The bills named in the Revisor's session-law citations: each RSMo section version's history note and each repeal
-- note, split into one row per (section version, act, bill). A history note lists the acts that made the section:
-- "(L. 1945 p. 1428 § 48, A.L. 2003 S.B. 299 & 40)" is enacted in 1945 (session-law page, no bill number) and
-- amended in 2003 by SB 299 and SB 40 (combined); "merged with" joins bills that changed the same section in one
-- session; "1st Ex. Sess." names an extraordinary session (the Revisor also prints "2d", "3d", "4th", "1st.", "lst",
-- "First" ... "Fourth", and "Ex. Sess" without its last period). change is enacted (L.), amended (A.L., or "A." in
-- the 1949 revision's notes) or repealed ("Repealed L."). Acts cited by page ("p. 1428") name no bill and are left out.
-- session_code follows the House XML codes: two-digit year, then 1 for the regular session. The House numbers every
-- special session (codes 2-4, in order), but the Revisor counts only extraordinary sessions that passed bills: 2018's
-- legislature-called impeachment session (183, resolutions only) isn't one, so the Revisor's 2018 "1st Ex. Sess." is
-- House 184. So the Nth extraordinary session is the House's session named "Nth Extraordinary Session"
-- (stg_mo_house__sessions); for years the House's list lacks, N + 2 is assumed. "Extraordinary Session" with no
-- number (1997's three "Repealed L." notes) is the year's only numbered session if the other notes name just one
-- (1997: "2d"), else the 1st.
-- A combined act ("H.B. 115 & 99": one substitute that carries several bills' subjects) names the bills after "&";
-- only the first, the lead bill (is_lead_bill), is the one that passed. The others stay as rows, with combined_into
-- naming the lead, because the act did take their subjects, but they never reached the governor themselves. A bill
-- after "&" may repeat its bill head ("H.B. 237 & H.B. 238 & H.B. 482", "H.B. 5 & S.B. 7"); a bare number takes the
-- type of the bill before it ("H.B. 69 & 179 & H.B. 669"). "and" ("H.B. 1270 and H.B. 2032") is ambiguous: the
-- Revisor uses it both for bills of one combined act (2004 "S.B. 968 and S.B. 969" is one act, lead SB 968) and for
-- separate acts ("H.B. 1606 and S.B. 743" in 2018, SB 743 also cited alone). A bill after "and" is its own lead bill
-- only when the same year and session cite it as the first bill of an act elsewhere (in any section's notes);
-- otherwise it is combined like one after "&", into the lead bill of its group (every bill up to the next separate
-- lead). The Revisor's "H.B. 1268 & 1211 and S.B. 966" is HB1211 combined into HB1268, with SB966 a lead only if
-- 2004 cites SB 966 on its own somewhere.
-- The older notes also list several bills of one act after commas ("A.L. 1978 H.B. 971, S.B. 628"). A piece that is
-- only a bill ("S.B. 628", "merged with S.B. 5") continues the act before it (same year, session and change), as
-- long as only such pieces come between (or the act is just a year, "A.L. 1985, H.B. 366"); after a page cite
-- ("p. 509") or an RSMo piece there is no act to continue.
-- A section cite may follow a bill ("H.B. 1574 § 6 and S.B. 721 § 2", "H.B. 1807, et al. § 301.4044 and S.B. 480"):
-- it is read past, so the bill after "and" is kept; the typo ".S.B. 58" (stray period) is read as "S.B. 58".
-- Parse bounds (macros/session_law_bounds.sql): a note is read up to 60 acts (longest real note: 43, RSMo 301.010), an
-- act up to 10 "merged with" bills (longest: 6) and 6 "&"/"and" bills (longest: 4). Parts past a bound would be dropped
-- silently, and notes list acts oldest first, so the newest acts would go; assert_session_law_bounds_not_exceeded
-- fails the build when real data needs more.
{# act: "Repealed L. 2018 ...", "A.L. 2003 ...", "L. 1945 ...", "A. 1949 ..."; bill: "H.B.", "S.B", "S.J.R.", "SJR" #}
{% set act_head = '^(Repealed )?(A\\.L\\.|L\\.|A\\.) ' %}
{% set bill_item = '[HS]\\.? ?[BJC]\\.? ?R?\\.? ?' %}
{% set bill_head = '^' ~ bill_item %}
{# extraordinary session: "1st", "2nd", "2d", "3d", "4th", "1st.", the OCR "lst", or "First" ... "Fourth"; the ordinal
   is optional ("Extraordinary Session", "Ex. Sess.") #}
{% set ex_ord = '([1-9l](st|nd|rd|d|th)\\.?|First|Second|Third|Fourth)' %}
{% set ex_sess = '((' ~ ex_ord ~ ' )?(Ex\\. ?Sess\\.?|Extraordinary Session))' %}
{# Parse bounds (macros/session_law_bounds.sql): split_part_at drops parts past its maximum, so a guard test fails the
   build when real data needs more. Today: 60 acts per note (longest real note: 43), 10 "merged with" bills per act
   (longest: 6), 6 "&"/"and" bills per act (longest: 4). #}
{% set bounds = mogov.session_law_bounds() %}
{% set max_acts = bounds.max_acts %}
{% set max_merged = bounds.max_merged %}
{% set max_combined = bounds.max_combined %}

with notes as (
    select
        section_id,
        section_version_id,
        'history' as note_kind,
        history_note as note
    from {{ ref('stg_mo_revisor__sections') }}
    where history_note is not null

    union all

    select
        section_id,
        section_version_id,
        'repeal' as note_kind,
        note
    from {{ ref('stg_mo_revisor__repeals') }}
    where change_kind = 'repealed'
),

normalized as (
    select
        section_id,
        section_version_id,
        note_kind,
        -- one separator between acts; "et al." belongs to the act before it
        {{ mogov.normalize_session_law_note('note') }} as note
    from notes
),

spine as (
    select cast(generated_number as {{ dbt.type_int() }}) as n
    from ({{ dbt_utils.generate_series(max_acts) }}) as s
),

acts as (
    select
        o.section_id,
        o.section_version_id,
        o.note_kind,
        s.n as act_index,
        trim({{ mogov.split_part_at('o.note', "', '", 's.n', max_acts) }}) as act
    from normalized as o
    cross join spine as s
    where s.n <= {{ dbt.length('o.note') }} - {{ dbt.length(dbt.replace('o.note', "','", "''")) }} + 1
),

-- "@" marks an act the note joined with " and L." (normalize_session_law_note): it follows its previous act's change
acts_marked as (
    select
        section_id,
        section_version_id,
        note_kind,
        act_index,
        act like '@%' as after_and_l,
        {{ mogov.regex_replace_all('act', '^@', '') }} as act
    from acts
),

acts_flagged as (
    select
        *,
        {{ mogov.regex_matches('act', act_head ~ '[0-9]{4}') }} as is_head,
        {{ mogov.regex_matches('act', '^(merged with )?' ~ bill_item ~ '[0-9]') }} as is_continuation
    from acts_marked
),

-- the last piece before each continuation that isn't itself a continuation: the act it continues, if that is an act
-- that names a bill ("A.L. 1978 H.B. 971, S.B. 628")
last_break as (
    select
        c.section_id,
        c.section_version_id,
        c.note_kind,
        c.act_index,
        max(b.act_index) as break_index
    from acts_flagged as c
    inner join acts_flagged as b
        on
            c.section_version_id = b.section_version_id
            and c.note_kind = b.note_kind
            and c.act_index > b.act_index
            and not b.is_continuation
    where c.is_continuation
    group by c.section_id, c.section_version_id, c.note_kind, c.act_index
),

acts_resolved as (
    select
        section_id,
        section_version_id,
        note_kind,
        act_index,
        after_and_l,
        act
    from acts_flagged
    where is_head

    union all

    select
        c.section_id,
        c.section_version_id,
        c.note_kind,
        c.act_index,
        h.after_and_l,
        -- the head's "A.L. 1978" (and session), then the continuing piece
        {{ mogov.regex_extract('h.act', '^((Repealed )?(A\\.L\\.|L\\.|A\\.) [0-9]{4}( ' ~ ex_sess ~ ')?)( |$)', 1) }}
        || ' ' || {{ mogov.regex_replace_all('c.act', '^merged with ', '') }} as act
    from acts_flagged as c
    inner join last_break as l
        on
            c.section_version_id = l.section_version_id
            and c.note_kind = l.note_kind
            and c.act_index = l.act_index
    inner join acts_flagged as h
        on
            l.section_version_id = h.section_version_id
            and l.note_kind = h.note_kind
            and l.break_index = h.act_index
    where
        c.is_continuation
        and h.is_head
        -- an act that names a bill, or a year alone ("A.L. 1985, H.B. 366": a stray comma after the year)
        and {{ mogov.regex_matches('h.act', act_head ~ '[0-9]{4}( ' ~ ex_sess ~ ')?( ' ~ bill_item ~ '[0-9]|$)') }}
),

own_change as (
    select
        *,
        case
            when act like 'Repealed %' then 'repealed'
            when act like 'A.L. %' or act like 'A. %' then 'amended'
            else 'enacted'
        end as change
    from acts_resolved
),

-- a bare "L." joined with " and L." to a repealed act is repealed too: "Repealed" in a repeal note covers the list
-- ("Repealed L. A and L. B and L. C": B and C are repealed). An "and L." act follows the nearest act before it that
-- was not joined that way (its anchor), not the act just before it, which may itself be an inheriting one; a
-- continuation piece after an "and L." head ("@L. B S.B. 5, S.B. 6") shares the head's flag, so it gets the same.
anchored as (
    select
        *,
        max(case when not after_and_l then act_index end) over (
            partition by section_id, section_version_id, note_kind
            order by act_index
        ) as anchor_index
    from own_change
),

inherited_change as (
    select
        a.*,
        case
            when a.after_and_l and p.change = 'repealed' then 'repealed'
            else a.change
        end as final_change
    from anchored as a
    left join own_change as p
        on
            a.section_id = p.section_id
            and a.section_version_id = p.section_version_id
            and a.note_kind = p.note_kind
            and a.anchor_index = p.act_index
),

parsed_acts as (
    select
        section_id,
        section_version_id,
        note_kind,
        act_index,
        act,
        final_change as change,
        {{ dbt.safe_cast(mogov.regex_extract('act', act_head ~ '([0-9]{4})', 3), dbt.type_int()) }} as act_year,
        {{ mogov.regex_extract('act', act_head ~ '[0-9]{4} ' ~ ex_ord ~ ' (Ex\\.|Extraordinary)', 3) }} as ex_ordinal,
        {{ mogov.regex_matches('act', act_head ~ '[0-9]{4} ' ~ ex_sess ~ ' ') }} as is_extra,
        {#- what follows the year (and the session): the bill references #}
        {{ mogov.regex_replace_all(
            mogov.regex_replace_all('act', act_head ~ '[0-9]{4} ', ''), '^' ~ ex_sess ~ ' ', ''
        ) }} as refs
    from inherited_change
),

numbered as (
    select
        *,
        case
            when ex_ordinal = 'First' then 1
            when ex_ordinal = 'Second' then 2
            when ex_ordinal = 'Third' then 3
            when ex_ordinal = 'Fourth' then 4
            else {{ dbt.safe_cast(
                dbt.replace(mogov.regex_extract('ex_ordinal', '^([1-9l])', 1), "'l'", "'1'"), dbt.type_int()
            ) }}
        end as ordinal_number
    from parsed_acts
),

-- a year whose notes all name the same extraordinary session number: "Extraordinary Session" without one is that
year_ordinals as (
    select
        act_year,
        min(ordinal_number) as ordinal_number
    from numbered
    where ordinal_number is not null
    group by act_year
    having count(distinct ordinal_number) = 1
),

sessioned as (
    select
        n.section_id,
        n.section_version_id,
        n.note_kind,
        n.act_index,
        n.act,
        n.change,
        n.act_year,
        case
            when not n.is_extra then null
            else coalesce(n.ordinal_number, y.ordinal_number, 1)
        end as extra_session,
        n.refs
    from numbered as n
    left join year_ordinals as y on n.act_year = y.act_year
),

merged as (
    select
        a.section_id,
        a.section_version_id,
        a.note_kind,
        a.act_index,
        a.act,
        a.change,
        a.act_year,
        a.extra_session,
        s.n as ref_index,
        trim({{ mogov.split_part_at('a.refs', "' merged with '", 's.n', max_merged) }}) as ref
    from sessioned as a
    cross join spine as s
    where
        s.n <= {{ max_merged }}
        and {{ mogov.split_part_at('a.refs', "' merged with '", 's.n', max_merged) }} <> ''
),

-- "H.B. 1574 § 6 and S.B. 721 § 2" (a section cite, with its "et al." and "subsec.", between bills joined by "and")
-- reads as "H.B. 1574 and S.B. 721"; the typo ".S.B. 58" (stray period) loses it. Without this the second bill is
-- dropped, as numbers stops at the first section cite.
bills_joined as (
    select
        *,
        {{ mogov.regex_replace_all(
            dbt.replace('ref', "' and .'", "' and '"),
            '( et al\.)? § [0-9A-Za-z.]+( subsec\. [0-9A-Za-z]+)? and ',
            ' and '
        ) }} as joined_ref
    from merged
),

typed as (
    select
        *,
        -- "299 & 40 § A Revision" -> "299 & 40"; "H.B. 1270 and H.B. 2032" -> "H.B. 1270 & @H.B. 2032" (@ marks a bill
        -- after "and": a lead bill only if cited as one elsewhere, see cited_leads)
        {{ dbt.replace(
            mogov.regex_extract('joined_ref', '^(' ~ bill_item ~ '[0-9]+( (&|and) (' ~ bill_item ~ ')?[0-9]+)*)', 1),
            "' and '",
            "' & @'"
        ) }} as numbers
    from bills_joined
),

items as (
    select
        t.section_id,
        t.section_version_id,
        t.note_kind,
        t.act_index,
        t.act,
        t.change,
        t.act_year,
        t.extra_session,
        t.ref_index,
        s.n as item_n,
        trim({{ dbt.replace(mogov.split_part_at('t.numbers', "' & '", 's.n', max_combined), "'@'", "''") }}) as item,
        {{ mogov.split_part_at('t.numbers', "' & '", 's.n', max_combined) }} like '@%' as after_and
    from typed as t
    cross join spine as s
    where
        t.numbers is not null
        and s.n <= {{ max_combined }}
        and {{ mogov.split_part_at('t.numbers', "' & '", 's.n', max_combined) }} <> ''
),

item_types as (
    select
        *,
        -- "H.B.", "S.B", "S.J.R.", "SJR" -> HB, SB, SJR; a bare number ("& 179") has no head of its own
        {{ mogov.regex_replace_all(mogov.regex_extract('item', '^(' ~ bill_item ~ ')[0-9]', 1), '[^A-Z]', '') }}
            as own_type,
        {{ mogov.regex_extract('item', '([0-9]+)$', 1) }} as number,
        -- the nearest item at or before this one that has a bill head
        max(case when {{ mogov.regex_matches('item', bill_head ~ '[0-9]') }} then item_n end) over (
            partition by section_id, section_version_id, note_kind, act_index, ref_index
            order by item_n
        ) as head_item
    from items
),

item_bills as (
    select
        i.*,
        h.own_type as bill_type
    from item_types as i
    inner join item_types as h
        on
            i.section_id = h.section_id
            and i.section_version_id = h.section_version_id
            and i.note_kind = h.note_kind
            and i.act_index = h.act_index
            and i.ref_index = h.ref_index
            and i.head_item = h.item_n
),

-- bills cited as the first bill of an act, by year and session: the "and" bills that count as separate leads
cited_leads as (
    select distinct
        act_year,
        coalesce(extra_session, 0) as extra_session,
        bill_type,
        number
    from item_bills
    where item_n = 1
),

item_groups as (
    select
        b.*,
        -- the item that starts this item's group of combined bills: item 1, or a bill after "and" that is also cited
        -- as the first bill of an act elsewhere in its year and session
        max(case when b.item_n = 1 or (b.after_and and c.number is not null) then b.item_n end) over (
            partition by b.section_id, b.section_version_id, b.note_kind, b.act_index, b.ref_index
            order by b.item_n
        ) as group_start
    from item_bills as b
    left join cited_leads as c
        on
            b.act_year = c.act_year
            and coalesce(b.extra_session, 0) = c.extra_session
            and b.bill_type = c.bill_type
            and b.number = c.number
),

bills as (
    select
        b.section_id,
        b.section_version_id,
        b.note_kind,
        b.act_index,
        b.act,
        b.change,
        b.act_year,
        b.extra_session,
        b.ref_index,
        b.bill_type,
        b.number as bill_number,
        b.item_n = b.group_start as is_lead_bill,
        l.bill_type || l.number as lead_bill
    from item_groups as b
    inner join item_groups as l
        on
            b.section_id = l.section_id
            and b.section_version_id = l.section_version_id
            and b.note_kind = l.note_kind
            and b.act_index = l.act_index
            and b.ref_index = l.ref_index
            and b.group_start = l.item_n
),

-- "1st Extraordinary Session" -> 1; the House's "Special Session" (2018's resolutions-only one) isn't counted
extra_sessions as (
    select
        session_year,
        session_code,
        {{ dbt.safe_cast(mogov.regex_extract('session_of_general_assembly', '^([0-9]+)', 1), dbt.type_int()) }}
            as ordinal
    from {{ ref('stg_mo_house__sessions') }}
    where session_of_general_assembly like '%Extraordinary Session'
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
    b.is_lead_bill,
    case when b.is_lead_bill then null else b.lead_bill end as combined_into,
    b.act
from bills as b
left join extra_sessions as x on b.act_year = x.session_year and b.extra_session = x.ordinal
