-- Roll-call votes on bills whose subject touches an industry or interest that gave the official money in or
-- before the vote's year: the official's vote, the bill, the subjects that tie it to the industry
-- (industry_subjects seed over the legislature's subject index) and the money (int_interests__industry_money).
-- Co-occurrence, not causation: it shows that money and a vote meet, not that one caused the other.
-- Only Missouri legislators: bill subjects (fct_bill_subjects) link to state votes only.
with votes as (
    select
        v.official_id,
        v.chamber,
        -- the bill's session code: Senate votes carry the journal year ('2026'), bills the House code ('261')
        vb.session_code,
        v.vote_id,
        v.vote_date,
        v.vote_description,
        v.vote_cast,
        v.source_url as vote_source_url,
        vb.bill,
        cast(extract(year from v.vote_date) as {{ dbt.type_int() }}) as vote_year
    from {{ ref('fct_votes') }} as v
    inner join {{ ref('fct_vote_bills') }} as vb
        on v.chamber = vb.chamber and v.vote_id = vb.vote_id
),

bill_industries as (
    select distinct
        s.session_code,
        s.bill,
        i.industry,
        s.subject_name
    from {{ ref('fct_bill_subjects') }} as s
    inner join {{ ref('industry_subjects') }} as i on s.subject_name = i.subject_name
),

bill_industry_subjects as (
    select
        session_code,
        bill,
        industry,
        {{ dbt.listagg('subject_name', "'; '", 'order by subject_name') }} as matched_subjects
    from bill_industries
    group by session_code, bill, industry
),

money_by_vote as (
    -- per bill, so money isn't summed once per bill when a vote covers several bills of one industry
    select
        v.official_id,
        v.chamber,
        v.vote_id,
        v.bill,
        b.industry,
        sum(case when m.money_kind = 'contribution' then m.total_amount else 0 end) as contributions_amount,
        sum(case when m.money_kind = 'lobbyist gift' then m.total_amount else 0 end) as gifts_amount,
        min(m.money_year) as first_money_year,
        max(m.money_year) as last_money_year,
        case when min(m.match_confidence) = 'high' and max(m.match_confidence) = 'high' then 'high' else 'medium' end
            as match_confidence
    from votes as v
    inner join bill_industry_subjects as b
        on v.session_code = b.session_code and v.bill = b.bill
    inner join {{ ref('int_interests__industry_money') }} as m
        on
            v.official_id = m.official_id
            and b.industry = m.industry
            and v.vote_year >= m.money_year
    group by v.official_id, v.chamber, v.vote_id, v.bill, b.industry
)

select
    v.official_id,
    v.chamber,
    v.session_code,
    v.vote_id,
    v.vote_date,
    v.vote_description,
    v.bill,
    bl.short_title,
    v.vote_cast,
    m.industry,
    b.matched_subjects,
    m.contributions_amount,
    m.gifts_amount,
    m.first_money_year,
    m.last_money_year,
    m.match_confidence,
    v.vote_source_url,
    bl.source_url as bill_source_url
from money_by_vote as m
inner join votes as v
    on m.official_id = v.official_id and m.chamber = v.chamber and m.vote_id = v.vote_id and m.bill = v.bill
inner join bill_industry_subjects as b
    on v.session_code = b.session_code and v.bill = b.bill and m.industry = b.industry
left join {{ ref('fct_bills') }} as bl
    on v.session_code = bl.session_code and v.bill = bl.bill
