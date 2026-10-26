{{ config(enabled=var('cl_case_bulk', false)) }}
-- Federal district-court dockets (E.D. and W.D. Missouri) that have an assigned judge: filed and terminated
-- dates (null when the docket has none) and the days between. A docket whose termination date is before its
-- filing date has a negative duration (a source error): it is kept and flagged with ends_before_filed, and the
-- judge metric leaves it out. The state courts carry no judge or dates in the bulk export, so only the federal
-- districts are here.
-- case_type comes from the docket-number type: the federal_dn_case_type CourtListener parsed when it has one
-- (empty for about 84% of these dockets), else the type token of the docket number itself ("4:25-cr-00236" is
-- cr). Mapped to civil (cv, and md: multidistrict-litigation master dockets, which carry civil nature-of-suit
-- codes), criminal (cr), miscellaneous (mc, mj, sw, wi, sm, pr: warrants, subpoenas, complaints, special
-- matters and the like, not cases) and other (fp, sc, cn and docket numbers with no type: a few dozen
-- pre-2008 filings the maintainer has not ruled on, #321). The CourtListener type wins where the two
-- disagree: the one such docket (1:00-cr-00008) is a civil suit with a mistyped docket number.
with typed as (
    select
        docket_id,
        court_id,
        assigned_to_person_id,
        date_filed,
        date_terminated,
        lower(trim(coalesce(nullif(federal_dn_case_type, ''), {{ dbt.split_part('docket_number', "'-'", 2) }})))
            as docket_type
    from {{ ref('stg_courtlistener__mo_dockets') }}
    where
        court_id in ('moed', 'mowd')
        and assigned_to_person_id is not null
)

select
    docket_id,
    court_id,
    assigned_to_person_id as cl_person_id,
    docket_type,
    case
        when docket_type in ('cv', 'md') then 'civil'
        when docket_type = 'cr' then 'criminal'
        when docket_type in ('mc', 'mj', 'sw', 'wi', 'sm', 'pr') then 'miscellaneous'
        else 'other'
    end as case_type,
    date_filed,
    date_terminated,
    date_filed is not null and date_terminated is not null as has_both_dates,
    {{ dbt.datediff('date_filed', 'date_terminated', 'day') }} as days_to_disposition,
    date_terminated < date_filed as ends_before_filed
from typed
