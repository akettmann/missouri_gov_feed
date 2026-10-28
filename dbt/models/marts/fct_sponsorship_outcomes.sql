-- What became of the bills each House member sponsored, per member and House session: counts from the House's own
-- bill actions (int_bills__status), shown with their n; not a score.
-- Counted: the primary sponsor (sponsor_type 'Sponsor', one per bill) of a House bill (HB) or House joint resolution
-- (HJR: a proposed law or constitutional amendment), sponsor_chamber state_house, matched to an official. Left out:
-- co-sponsors, handlers and conferees; resolutions (HR, HCR: adopted by voice vote or not at all, they would swamp
-- the share); Senate bills and their senator sponsors (fct_bill_sponsors lists them since #839, as state_senate;
-- bill_type below keeps only HB and HJR). fct_bill_sponsors already drops the re-listed
-- appropriation bills. Appropriation bills are kept: they are real sponsorships, and the Budget chair
-- carries them, almost all passing.
-- bills_decided is the denominator: bills whose outcome is known, so not 'pending' (session still open) or
-- 'awaiting governor' (truly agreed this year). 'no governor action recorded' counts as decided but not as law.
-- bills_passed_house and bills_became_law count within the decided bills, so each share stays within 0 to 1.
-- Only current officials (dim_official) have an official_id, so former members are not here.
with sponsored as (
    select distinct
        sp.official_id,
        sp.session_code,
        sp.bill
    from {{ ref('fct_bill_sponsors') }} as sp
    where
        sp.sponsor_type = 'Sponsor'
        and sp.sponsor_chamber = 'state_house'
        and sp.official_id is not null
),

bills as (
    select
        s.official_id,
        s.session_code,
        st.session_year,
        st.is_session_over,
        st.bill_type,
        st.passed_house,
        st.outcome,
        coalesce(st.outcome not in ('pending', 'awaiting governor'), false) as is_decided
    from sponsored as s
    inner join {{ ref('int_bills__status') }} as st on s.session_code = st.session_code and s.bill = st.bill
    where st.bill_type in ('HB', 'HJR')
),

counts as (
    select
        official_id,
        session_code,
        session_year,
        is_session_over,
        count(*) as bills_sponsored,
        sum(case when is_decided then 1 else 0 end) as bills_decided,
        sum(case when is_decided and passed_house then 1 else 0 end) as bills_passed_house,
        sum(case
            when bill_type = 'HB' and outcome = 'enacted' then 1
            when bill_type = 'HJR' and outcome = 'sent to voters' then 1
            else 0
        end) as bills_became_law
    from bills
    group by official_id, session_code, session_year, is_session_over
)

select
    official_id,
    session_code,
    session_year,
    is_session_over,
    cast(bills_sponsored as {{ dbt.type_bigint() }}) as bills_sponsored,
    cast(bills_decided as {{ dbt.type_bigint() }}) as bills_decided,
    cast(bills_passed_house as {{ dbt.type_bigint() }}) as bills_passed_house,
    cast(bills_became_law as {{ dbt.type_bigint() }}) as bills_became_law,
    case
        when bills_decided > 0
            then cast(1.0 * bills_passed_house / bills_decided as {{ dbt.type_numeric() }})
    end as passed_house_share,
    case
        when bills_decided > 0
            then cast(1.0 * bills_became_law / bills_decided as {{ dbt.type_numeric() }})
    end as became_law_share,
    {{ dbt.concat(["'https://documents.house.mo.gov/xml/'", 'session_code', "'.zip'"]) }} as source_url
from counts
