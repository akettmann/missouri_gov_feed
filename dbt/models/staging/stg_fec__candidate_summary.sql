-- FEC all-candidates summary: per candidate per cycle totals.
select
    cand_id as candidate_id,
    cand_name as candidate_name,
    {{ dbt.safe_cast(mogov.regex_extract('filename', 'weball([0-9]{2})'), dbt.type_int()) }} + 2000 as cycle,
    {{ dbt.safe_cast('ttl_receipts', dbt.type_numeric()) }} as total_receipts,
    {{ dbt.safe_cast('ttl_disb', dbt.type_numeric()) }} as total_disbursements,
    {{ dbt.safe_cast('ttl_indiv_contrib', dbt.type_numeric()) }} as individual_contributions,
    {{ dbt.safe_cast('other_pol_cmte_contrib', dbt.type_numeric()) }} as pac_contributions,
    {{ dbt.safe_cast('pol_pty_contrib', dbt.type_numeric()) }} as party_contributions,
    {{ dbt.safe_cast('cand_contrib', dbt.type_numeric()) }} as candidate_self_contributions,
    {{ dbt.safe_cast('cand_loans', dbt.type_numeric()) }} as candidate_loans,
    {{ dbt.safe_cast('coh_cop', dbt.type_numeric()) }} as cash_on_hand_end,
    {{ dbt.safe_cast('debts_owed_by', dbt.type_numeric()) }} as debts_owed
from {{ source('raw', 'fec_candidate_summary') }}
