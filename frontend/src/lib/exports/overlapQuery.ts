/**
 * SQL for each official's example votes per industry in rpt_interest_vote_overlap (`overlap` is a table
 * expression, a `{rpt_interest_vote_overlap}` placeholder in load.ts). One example per bill and session, newest bills first.
 * A bill often has several roll calls the same day (SB724 on 2022-05-10 has 25), so the one shown is the most
 * meaningful of that bill's latest day:
 *   1. final passage ("read the 3rd time and passed", "finally passed" in the Senate journal text);
 *      a motion to reconsider a passage vote also says "finally passed", so any "reconsider" goes to tier 2 first,
 *   2. any other question (adopting a conference report, an emergency clause, a House version),
 *   3. an amendment ("SA 2", "HA 1", "SSA 1", "amendment").
 * Ties (all House roll calls: the PDF carries only the calendar item, so a House amendment looks like passage)
 * go to the day's last roll call, since a bill's amendments are voted before the bill itself. Roll-call order
 * is the vote_id's length, then the id: Senate ids end in `#vote<n>` and plain string order puts vote10 before
 * vote2. Every sort key ends in a unique one, so the output does not depend on row order (#226).
 */
export function overlapExamplesSql(examples: number, overlap: string): string {
  return `
      select official_id, industry, cast(vote_date as varchar) as vote_date, bill, short_title, vote_cast,
             vote_source_url, bill_source_url
      from (
        select *, row_number() over (partition by official_id, industry order by vote_date desc, bill, session_code) as rank
        from (
          select *, row_number() over (
                   partition by official_id, industry, session_code, bill
                   order by vote_date desc,
                     case
                       when lower(coalesce(vote_description, '')) like '%reconsider%' then 1
                       when lower(coalesce(vote_description, '')) like '%time and passed%'
                         or lower(coalesce(vote_description, '')) like '%finally passed%' then 0
                       when regexp_matches(lower(coalesce(vote_description, '')), '(^|[^a-z])[sh]s?a ?[0-9]')
                         or lower(coalesce(vote_description, '')) like '%amendment%' then 2
                       else 1
                     end,
                     length(vote_id) desc, vote_id desc, chamber
                 ) as pick
          from ${overlap}
        ) as per_bill
        where pick = 1
      ) ranked
      where rank <= ${examples}
      order by official_id, industry, rank`;
}
