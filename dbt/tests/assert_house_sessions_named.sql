-- Sanity check (warn): every House session code the attendance and committee-post marts carry has a name in
-- dim_house_session, so the frontend never has to fall back to "session code NNN". The open session may
-- legitimately be unlisted until the House publishes its first list. Returns each unnamed (model, session_code).
{{ config(severity='warn') }}

with used as (
    select distinct
        'rpt_attendance' as model_name,
        session_code
    from {{ ref('rpt_attendance') }}
    where chamber = 'state_house'

    union all

    select distinct
        'fct_committee_posts' as model_name,
        session_code
    from {{ ref('fct_committee_posts') }}
)

select
    used.model_name,
    used.session_code
from used
left join {{ ref('dim_house_session') }} as sessions
    on used.session_code = sessions.session_code
where sessions.session_code is null
