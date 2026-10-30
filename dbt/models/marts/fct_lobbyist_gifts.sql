-- Lobbyist expenditures on current officials (meals, tickets, travel, gifts), from MEC lobbyist reports
-- (TAP mirror, 2004-2022). Missouri's Amendment 1 (Dec 2018) banned most gifts over $5, so volumes drop
-- sharply after 2018. Matched on recipient "LAST, FIRST" + office title; confidence 'high' when the first
-- name matches exactly, 'medium' when only its first three letters do (Dan/Daniel, Rob/Robert; not
-- Mike/Michael, whose first three letters differ).
-- With the opt-in MEC loader, 2019+ comes from MEC directly and the mirror supplies earlier years.
-- Grain: (official_id, gift_key). The lobbyist reports carry no per-row id (TAP's ind_id repeats across rows), so
-- gift_key hashes every reported field plus the occurrence number among identical rows: two identical $25
-- meals the same day are real, distinct entries.
with all_gifts as (
    select
        lobbyist_id,
        lobbyist_name,
        principal_name,
        recipient_raw,
        upper(recipient_title) as recipient_title,
        recipient_last,
        recipient_first,
        expenditure_category,
        description,
        amount,
        expenditure_date,
        'MEC lobbyist reports (via Accountability Project)' as source
    from {{ ref('stg_tap_mec__lobbyist_gifts') }}
    {% if var('mec_direct', false) %}
        where expenditure_date < {{ dbt.safe_cast("'2019-01-01'", 'date') }}
        union all
        select
            lobbyist_id,
            lobbyist_name,
            principal_name,
            recipient_raw,
            upper(recipient_title) as recipient_title,
            recipient_last,
            recipient_first,
            expenditure_category,
            description,
            amount,
            expenditure_date,
            'MEC lobbyist reports' as source
        from {{ ref('stg_mec__lobbyist_gifts') }}
    {% endif %}
),

keyed as (
    select
        *,
        row_number() over (
            partition by
                lobbyist_id, lobbyist_name, principal_name, recipient_raw, recipient_title, recipient_last,
                recipient_first, expenditure_category, description, amount, expenditure_date, source
            order by amount
        ) as occurrence
    from all_gifts
),

gifts as (
    select
        *,
        {{ dbt_utils.generate_surrogate_key([
            'lobbyist_id', 'lobbyist_name', 'principal_name', 'recipient_raw', 'recipient_title', 'recipient_last',
            'recipient_first', 'expenditure_category', 'description', 'amount', 'expenditure_date', 'source',
            'occurrence'
        ]) }} as gift_key,
        extract(year from expenditure_date) as expenditure_year,
        {{ mogov.name_key('recipient_last') }} as last_key,
        {{ mogov.name_key(dbt.split_part('recipient_first', "' '", 1)) }} as first_key
    from keyed
    where recipient_last is not null and recipient_first is not null
),

officials as (
    select distinct
        official_id,
        office,
        family_key,
        given_key
    from {{ ref('int_officials__name_keys') }}
    where level = 'state'
),

matched as (
    select
        o.official_id,
        g.*,
        case when g.first_key = o.given_key then 'high' else 'medium' end as match_confidence,
        count(distinct o.official_id) over (
            partition by g.lobbyist_id, g.expenditure_date, g.recipient_raw, g.amount, g.description
        ) as n_officials
    from gifts as g
    inner join officials as o
        on
            g.last_key = o.family_key
            and left(g.first_key, 3) = left(o.given_key, 3)
            and (
                g.recipient_title in (
                    'REPRESENTATIVE', 'SENATOR', 'PUBLIC OFFICIAL', 'SPOUSE OR CHILD', 'STATEWIDE OFFICIAL'
                )
                or g.recipient_title like '%' || upper(replace(o.office, '_', ' ')) || '%'
                or g.recipient_title is null
            )
)

select
    official_id,
    expenditure_date,
    expenditure_year,
    amount,
    lobbyist_name,
    principal_name as lobbyist_principal,
    expenditure_category,
    description,
    recipient_title,
    recipient_raw,
    match_confidence,
    source,
    gift_key
from matched
where n_officials = 1
