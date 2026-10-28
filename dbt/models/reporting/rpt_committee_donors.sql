-- One hop back: for each Missouri committee that gave to an official (fct_campaign_finance's
-- counterparty_mec_committee_id), who gave to that committee, over every year loaded (both MEC feeds).
-- Its 10 largest non-individual donors are listed (donor_rank 1-10, a strict order: amount ties break by
-- donor_name, then donor_class, which with the committee is the grain's key, so a rank is never shared or
-- flipped); itemized individuals are summed into one row (donor_class 'individual', no rank), since a
-- person's name is not an organization to follow.
-- trail_status says whether the trail goes on:
--   mec committee          the donor is a committee whose name matches one Missouri filer (donor_mec_committee_id)
--   ambiguous mec name     several Missouri committees active that year share the name
--   not an mec filer       a committee not found among Missouri filers (federal and out-of-state PACs report
--                          elsewhere, or a name too different to match)
--   own name               the donor name matches the receiving committee itself (a committee does not fund itself,
--                          so the trail is not followed, #833)
--   end of trail           a business or organization: MEC does not receive the donors of non-committees,
--                          so a nonprofit's funders are not disclosed here
--   individuals            itemized gifts from people
with committees as (
    select distinct counterparty_mec_committee_id as mec_committee_id
    from {{ ref('fct_campaign_finance') }}
    where direction = 'received' and counterparty_mec_committee_id is not null
),

latest_name as (
    select
        mec_committee_id,
        committee_name,
        row_number() over (
            partition by mec_committee_id order by coalesce(last_year_under_name, 0) desc, committee_name asc
        ) as name_rank
    from {{ ref('int_mec__committee_names') }}
),

gifts as (
    select
        r.mec_committee_id,
        r.amount,
        r.contribution_year,
        {{ mogov.donor_class('r.contributor_type') }} as donor_class,
        case
            when lower(r.contributor_type) = 'individual' then '(individuals)'
            else
                coalesce(
                    nullif(trim(r.contributor_committee_name), ''), nullif(trim(r.contributor_name), ''), '(unnamed)'
                )
        end as donor_name,
        x.match_status,
        x.mec_committee_id as donor_mec_committee_id,
        x.match_confidence as donor_link_confidence
    from {{ ref('int_mec__contributions_received') }} as r
    inner join committees as c on r.mec_committee_id = c.mec_committee_id
    left join {{ ref('int_mec__donor_committees') }} as x
        on r.contributor_committee_name = x.donor_committee_name and r.contribution_year = x.contribution_year
),

donors as (
    select
        mec_committee_id,
        donor_class,
        donor_name,
        sum(amount) as total_amount,
        count(*) as contribution_count,
        min(contribution_year) as first_year,
        max(contribution_year) as last_year,
        max(case when match_status = 'ambiguous' then 1 else 0 end) as any_ambiguous,
        max(case when donor_mec_committee_id = mec_committee_id then 1 else 0 end) as any_self
    from gifts
    group by mec_committee_id, donor_class, donor_name
),

-- a name can match in some years and not others (or two IDs over time): keep the ID with the most money.
-- A match to the committee itself is no link (#833): a committee does not fund itself, so the name is another
-- body's (for C000621 the parent union, "Missouri State Council of Fire Fighters", matched to its PAC once the
-- core-name tier dropped "PAC"). The money stays, as a donor we can't place; the trail doesn't loop back.
donor_links as (
    select
        mec_committee_id,
        donor_class,
        donor_name,
        donor_mec_committee_id,
        donor_link_confidence,
        row_number() over (
            partition by mec_committee_id, donor_class, donor_name
            order by sum(amount) desc, donor_mec_committee_id
        ) as link_rank
    from gifts
    where donor_mec_committee_id is not null and donor_mec_committee_id <> mec_committee_id
    group by mec_committee_id, donor_class, donor_name, donor_mec_committee_id, donor_link_confidence
),

ranked as (
    select
        d.mec_committee_id,
        d.donor_class,
        d.donor_name,
        d.total_amount,
        d.contribution_count,
        d.first_year,
        d.last_year,
        l.donor_mec_committee_id,
        l.donor_link_confidence,
        case
            when d.donor_class = 'individual' then 'individuals'
            when l.donor_mec_committee_id is not null then 'mec committee'
            when d.any_self = 1 then 'own name'
            when d.donor_class in ('business or organization', 'other') then 'end of trail'
            when d.any_ambiguous = 1 then 'ambiguous mec name'
            else 'not an mec filer'
        end as trail_status,
        case
            when d.donor_class <> 'individual'
                then row_number() over (
                    partition by d.mec_committee_id, case when d.donor_class = 'individual' then 1 else 0 end
                    order by d.total_amount desc, d.donor_name asc, d.donor_class asc
                )
        end as donor_rank,
        sum(d.total_amount) over (partition by d.mec_committee_id) as committee_total_amount
    from donors as d
    left join donor_links as l
        on
            d.mec_committee_id = l.mec_committee_id
            and d.donor_class = l.donor_class
            and d.donor_name = l.donor_name
            and l.link_rank = 1
)

select
    r.mec_committee_id,
    n.committee_name,
    r.committee_total_amount,
    r.donor_rank,
    r.donor_class,
    r.donor_name,
    r.total_amount,
    r.contribution_count,
    r.first_year,
    r.last_year,
    r.trail_status,
    r.donor_mec_committee_id,
    r.donor_link_confidence,
    'https://www.mec.mo.gov/MEC/Campaign_Finance/CF11_CommInfo.aspx?MECID=' || r.mec_committee_id as source_url
from ranked as r
left join latest_name as n on r.mec_committee_id = n.mec_committee_id and n.name_rank = 1
where r.donor_class = 'individual' or r.donor_rank <= 10
