{{ config(enabled=var('mec_direct', false)) }}
-- MEC contributions made: the reporting committee (mecid) gave to `committee` (a candidate or committee).
select
    mecid as mec_committee_id,
    committee_name,
    committee as recipient_name,
    {{ dbt.safe_cast('amount', dbt.type_numeric()) }} as amount,
    {{ mogov.parse_date(dbt.split_part('date', "' '", 1), '%m/%d/%Y') }} as contribution_date,
    contribution_type as contribution_kind,
    report,
    cd3_c_id as record_id
from {{ source('raw', 'mec_cd3_c') }}
