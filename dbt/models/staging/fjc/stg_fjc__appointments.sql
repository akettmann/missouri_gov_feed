-- Federal Judicial Center: one row per (judge, appointment). The CSV is wide with up to six
-- appointment groups "(1)".."(6)"; unpivot them with a union.
{% set q = adapter.quote %}
{% for k in range(1, 7) %}
    select
        nid as fjc_nid,
        jid as fjc_jid,
        {{ q('First Name') }} as given_name,
        {{ q('Middle Name') }} as middle_name,
        {{ q('Last Name') }} as family_name,
        {{ q('Suffix') }} as suffix,
        {{ q('Professional Career') }} as professional_career,
        {{ k }} as appointment_number,
        {{ q('Court Type (' ~ k ~ ')') }} as court_type,
        {{ q('Court Name (' ~ k ~ ')') }} as court_name,
        {{ q('Appointment Title (' ~ k ~ ')') }} as appointment_title,
        {{ q('Appointing President (' ~ k ~ ')') }} as appointing_president,
        {{ q('Party of Appointing President (' ~ k ~ ')') }} as appointing_party,
        {{ q('ABA Rating (' ~ k ~ ')') }} as aba_rating,
        {{ dbt.safe_cast(q('Commission Date (' ~ k ~ ')'), 'date') }} as commission_date,
        {{ dbt.safe_cast(q('Senior Status Date (' ~ k ~ ')'), 'date') }} as senior_status_date,
        {{ q('Termination (' ~ k ~ ')') }} as termination,
        {{ dbt.safe_cast(q('Termination Date (' ~ k ~ ')'), 'date') }} as termination_date
    from {{ source('fjc', 'judges') }}
    where {{ q('Court Name (' ~ k ~ ')') }} is not null
    {% if not loop.last %}union all{% endif %}
{% endfor %}
