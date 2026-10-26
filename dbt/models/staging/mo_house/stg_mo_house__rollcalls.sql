-- One row per MO House roll call (parsed PDF header). The line after "Roll Call : N" names the measure
-- (e.g. "HCS HB 10"); the next lines carry the sponsor and a description.
-- The House's rollcalls directory for a session holds PDFs that belong to other sessions; three rules drop them.
-- 1. Dated outside the session's year (#430): bills171 holds the 2016 session's PDFs (415 votes dated 2016, none
--    linked from the bill XML; they belong to session 161, which is not loaded).
-- 2. Header names another session (#435): the PDF header carries the General Assembly ("99th") and a session label
--    ("FIRST REGULAR SESSION", "SPECIAL SESSION", "SECOND EXTRAORDINARY SESSION"). A regular session (code ending
--    in 1) must show its General Assembly and the label FIRST in odd years, SECOND in even years; an extraordinary
--    or special session (any other last digit) must show its General Assembly and an EXTRAORDINARY or SPECIAL
--    label. Only a recognised label under the wrong kind of code drops a row; an unknown label is kept and fails
--    the accepted_values test on header_session_label. The House numbers extraordinary sessions irregularly (173
--    prints SPECIAL, 184 prints FIRST EXTRAORDINARY, 174 prints SECOND), so those labels are not
--    checked against the code's ordinal. Drops 5 PDFs:
--    171 002.001/002.002 (SPECIAL SESSION; voting-board test records, Y for the first six names alphabetically
--    or MORRIS+KIDD only; 173 has its own different 2.1/2.2), 201 012.001 (FIRST EXTRAORDINARY, a copy of 203's
--    012.001) and 204 003.002/003.003 (dated 2020-11-19, SECOND REGULAR SESSION: non-votes, voting-board
--    test/practice records under a regular-session header; HB 2315 was never third-read in 201, the PDFs show
--    3 Y/4 N with the rest absent and 25 Y/3 N of 161, and "Session Day : 3" is 204's own
--    counter). A header that does not parse (no PDF text) is kept.
-- 3. The same (session, day, roll-call number) published under two file names (#435): 261 has 003.001 = 003.002,
--    004.002 = 004.004 and 004.003 = 004.005, byte-identical headers and totals. The roll-call number printed in
--    the PDF is the key; the file whose name carries that number (else the first by URL) is kept.
-- 4. Voting-board test records (#449): a roll call on which hardly any member voted. A recorded vote needs a
--    quorum (a majority of the 163 seats, 82), and in 6,449 PDFs the fewest members who voted on a real roll call
--    is 83 (a quorum call); 211 sit between 83 and 120. Eight PDFs have 1 to 28 voters of 161 to 163: 171
--    002.001/002.002 (2 and 6), 173 002.001/002.002 (HUBRECHT alone on a QUORUM CALL; LOVE alone on a PQ), 231
--    026.003/026.004 (7 and 5 members on an ADJOURNMENT, the first names alphabetically, printed after the last
--    real vote of the day), 204 003.002/003.003 (10 and 28). A roll call where fewer than
--    var('house_rollcall_min_participation') (a quarter) of the listed members cast a vote is dropped; the 28-to-83
--    gap leaves room either way. A roll call with no parsed votes is kept. The singular test
--    assert_house_rollcalls_quorum_participation fails on any survivor under half the members (an allowlist
--    var holds genuine small-quorum calls).
-- Raw keeps everything.
{#- the file name that carries the roll call's own number, e.g. '%/003.001.pdf' -#}
{% set file_name_like = dbt.concat([
    "'%/'", mogov.zero_pad('session_day', 3), "'.'", mogov.zero_pad('rollcall_number', 3), "'.pdf'"
]) %}

with src as (
    select
        {{ mogov.json_str('payload', '$.url') }} as rollcall_url,
        {{ mogov.json_str('payload', '$.session_code') }} as session_code,
        {{ mogov.json_str('payload', '$.session_day') }} as session_day,
        {{ mogov.json_str('payload', '$.rollcall_number') }} as rollcall_number,
        {{ mogov.json_str('payload', '$.vote_date') }} as vote_date_text,
        {{ mogov.json_str('payload', '$.text') }} as header_text,
        {{ mogov.json_str('payload', '$.totals.Yes') }} as total_yes,
        {{ mogov.json_str('payload', '$.totals.No') }} as total_no,
        {{ mogov.json_str('payload', '$.error') }} as load_error
    from {{ source('mo_house', 'rollcalls') }}
),

participation as (
    select
        {{ mogov.json_str('payload', '$.url') }} as rollcall_url,
        count(*) as members_listed,
        sum(case when {{ mogov.json_str('payload', '$.vote_code') }} = '@' then 0 else 1 end) as members_voting
    from {{ source('mo_house', 'rollcall_votes') }}
    group by 1
),

parsed as (
    select
        rollcall_url,
        session_code,
        {{ dbt.safe_cast('session_day', dbt.type_int()) }} as session_day,
        {{ dbt.safe_cast('rollcall_number', dbt.type_int()) }} as rollcall_number,
        {{ mogov.parse_date('vote_date_text', '%m/%d/%Y') }} as vote_date,
        {{ dbt.safe_cast(mogov.regex_extract('header_text', '([0-9]+)(st|nd|rd|th) General Assembly'),
            dbt.type_int()) }} as header_general_assembly,
        trim({{ mogov.regex_extract('header_text', 'General Assembly[ \n]+([A-Z][A-Z ]*SESSION)') }})
            as header_session_label,
        trim({{ mogov.regex_extract('header_text', 'Session Day *: *[0-9]+ +([A-Z][^\n]*?) +Date') }}) as calendar_item,
        trim({{ mogov.regex_extract('header_text', 'Roll Call *: *[0-9]+ +([^\n]+)') }}) as measure,
        trim({{ mogov.regex_extract('header_text', '\n *([A-Z][A-Z .\'-]+ \\([0-9]{3}\\)) *\n') }}) as sponsor,
        {{ dbt.safe_cast('total_yes', dbt.type_int()) }} as total_yes,
        {{ dbt.safe_cast('total_no', dbt.type_int()) }} as total_no,
        2000 + {{ dbt.safe_cast("substring(session_code, 1, 2)", dbt.type_int()) }} as session_year,
        substring(session_code, 3, 1) = '1' as is_regular_session
    from src
    where load_error is null
),

checked as (
    select
        parsed.*,
        participation.members_listed,
        participation.members_voting,
        -- the General Assembly sitting in the session's year: 99th = 2017-2018, 100th = 2019-2020, ...
        (parsed.session_year - 1819 - mod(parsed.session_year - 1819, 2)) / 2 as session_general_assembly
    from parsed
    left join participation on parsed.rollcall_url = participation.rollcall_url
),

in_session as (
    select *
    from checked
    -- a roll call whose date didn't parse is kept (null passes)
    where
        (vote_date is null or extract(year from vote_date) = session_year)
        -- a header that didn't parse is kept (null passes)
        and (header_general_assembly is null or header_general_assembly = session_general_assembly)
        -- voting-board test records: hardly anyone voted (a roll call with no parsed votes is kept)
        and (
            members_listed is null
            or members_voting >= {{ var('house_rollcall_min_participation') }} * members_listed
        )
        -- drop only on a RECOGNISED label that belongs to another kind of session; an unknown label ("VETO SESSION")
        -- is kept so the accepted_values test on header_session_label fails loudly instead of rows vanishing
        and (
            header_session_label is null
            or case
                when
                    is_regular_session
                    then
                        not (
                            {{ mogov.regex_matches('header_session_label', '(EXTRAORDINARY|SPECIAL) SESSION$') }}
                            or (
                                header_session_label in ('FIRST REGULAR SESSION', 'SECOND REGULAR SESSION')
                                and header_session_label
                                != case when mod(session_year, 2) = 1 then 'FIRST' else 'SECOND' end
                                || ' REGULAR SESSION'
                            )
                        )
                else header_session_label not in ('FIRST REGULAR SESSION', 'SECOND REGULAR SESSION')
            end
        )
),

deduped as (
    select
        *,
        row_number() over (
            partition by
                session_code,
                session_day,
                rollcall_number,
                -- a roll call missing a key part stays on its own
                case when session_day is null or rollcall_number is null then rollcall_url end
            order by
                case
                    when rollcall_url like {{ file_name_like }}
                        then 0
                    else 1
                end,
                rollcall_url
        ) as key_rank
    from in_session
)

select
    rollcall_url,
    session_code,
    session_day,
    rollcall_number,
    vote_date,
    header_general_assembly,
    header_session_label,
    calendar_item,
    measure,
    sponsor,
    total_yes,
    total_no,
    members_listed,
    members_voting
from deduped
where key_rank = 1
