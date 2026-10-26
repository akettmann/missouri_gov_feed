-- Voteview member-congress rows, with DW-NOMINATE ideal points (dim1: economic left(-)/right(+)).
select
    {{ dbt.safe_cast('congress', dbt.type_int()) }} as congress,
    chamber,
    {{ dbt.safe_cast('icpsr', dbt.type_int()) }} as icpsr,
    state_abbrev,
    {{ dbt.safe_cast(dbt.safe_cast('district_code', dbt.type_float()), dbt.type_int()) }} as district_code,
    {{ dbt.safe_cast(dbt.safe_cast('party_code', dbt.type_float()), dbt.type_int()) }} as party_code,
    bioname,
    bioguide_id,
    {{ dbt.safe_cast('nominate_dim1', dbt.type_float()) }} as nominate_dim1,
    {{ dbt.safe_cast('nominate_dim2', dbt.type_float()) }} as nominate_dim2,
    {{ dbt.safe_cast(dbt.safe_cast('nominate_number_of_votes', dbt.type_float()), dbt.type_int()) }}
        as nominate_number_of_votes,
    {{ dbt.safe_cast('nokken_poole_dim1', dbt.type_float()) }} as nokken_poole_dim1,
    {{ dbt.safe_cast('nokken_poole_dim2', dbt.type_float()) }} as nokken_poole_dim2
from {{ source('voteview', 'members') }}
-- House and Senate only: the members file also lists the President, who has no chamber of his own
where chamber in ('House', 'Senate')
