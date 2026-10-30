{{ config(enabled=var('cl_case_bulk', false)) }}
-- Median days from filing to termination of the civil and criminal federal district-court dockets (E.D. and W.D.
-- Missouri) assigned to each judge, each case type apart (a criminal docket takes about twice as long as a civil
-- one and the mix differs by judge, so one combined median would compare case mix, not pace). Miscellaneous
-- dockets (mc, mj, sw, wi, sm, pr: warrants, subpoenas, complaints) are not cases and 'other' (unclassified old
-- docket types) is unruled; both are left out (see int_courtlistener__district_dockets), from the
-- CourtListener bulk export (var cl_case_bulk). One measured number per judge, shown with its n:
-- dockets_measured counts dockets with both dates and a non-negative duration. Dockets that end
-- before they were filed (a source error) are counted in dockets_ends_before_filed and left out of the median.
-- share_with_both_dates is the share of the judge's assigned dockets that have both dates, so a median from a
-- thin share can be read as such. Includes judges who no longer sit (official_id is null for those not in
-- dim_official). Dockets are those assigned to the judge on the docket record, regardless of which judge
-- finally decided them. Grain: one row per CourtListener judge and case type (civil, criminal).
with per_judge as (
    select
        cl_person_id,
        case_type,
        count(distinct court_id) as n_courts,
        min(court_id) as first_court,
        count(*) as dockets_assigned,
        sum(case when has_both_dates then 1 else 0 end) as dockets_with_both_dates,
        sum(case when ends_before_filed then 1 else 0 end) as dockets_ends_before_filed,
        sum(case when has_both_dates and not ends_before_filed then 1 else 0 end) as dockets_measured,
        {{ mogov.median('case when has_both_dates and not ends_before_filed then days_to_disposition end') }}
            as median_days_to_disposition
    from {{ ref('int_courtlistener__district_dockets') }}
    where case_type in ('civil', 'criminal')
    group by cl_person_id, case_type
)

select
    j.cl_person_id,
    j.case_type,
    op.official_id,
    trim(
        coalesce(p.name_first || ' ', '') || coalesce(p.name_middle || ' ', '') || coalesce(p.name_last, '')
        || coalesce(' ' || p.name_suffix, '')
    ) as judge_name,
    case when j.n_courts > 1 then 'moed+mowd' else j.first_court end as court_id,
    cast(j.dockets_assigned as {{ dbt.type_bigint() }}) as dockets_assigned,
    cast(j.dockets_with_both_dates as {{ dbt.type_bigint() }}) as dockets_with_both_dates,
    cast(j.dockets_ends_before_filed as {{ dbt.type_bigint() }}) as dockets_ends_before_filed,
    cast(j.dockets_measured as {{ dbt.type_bigint() }}) as dockets_measured,
    cast(j.dockets_with_both_dates as {{ dbt.type_float() }}) / j.dockets_assigned as share_with_both_dates,
    cast(j.median_days_to_disposition as {{ dbt.type_float() }}) as median_days_to_disposition
from per_judge as j
left join {{ ref('stg_courtlistener__people') }} as p on j.cl_person_id = cast(p.cl_person_id as varchar)
left join {{ ref('int_courtlistener__official_people') }} as op on j.cl_person_id = cast(op.cl_person_id as varchar)
