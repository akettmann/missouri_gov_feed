-- FEC pas2: contributions from committees (PACs, party committees, leadership PACs) to candidates,
-- plus independent expenditures for/against candidates. Amounts in USD; dates MMDDYYYY in the file.
select
    sub_id,
    cmte_id as giving_committee_id,
    cand_id as candidate_id,
    other_id as recipient_committee_id,
    name as recipient_name,
    transaction_tp as transaction_type,
    entity_tp as entity_type,
    {{ dbt.safe_cast('transaction_amt', dbt.type_numeric()) }} as amount,
    {{ mogov.parse_date('transaction_dt', '%m%d%Y') }} as transaction_date,
    case
        when transaction_tp = '24E' then 'independent expenditure supporting'
        when transaction_tp = '24A' then 'independent expenditure opposing'
        when transaction_tp in ('24K', '24Z') then 'direct contribution'
        when transaction_tp = '24C' then 'coordinated party expenditure'
        else 'other (' || transaction_tp || ')'
    end as transaction_kind,
    memo_cd as memo_code,
    image_num as image_number
from {{ source('raw', 'fec_committee_contribs_to_candidates') }}
where coalesce(memo_cd, '') <> 'X'
