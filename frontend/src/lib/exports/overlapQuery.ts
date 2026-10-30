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
 *
 * Recusals (Senate Rule 91, vote_cast = 'recused') are always listed too, even past the cap: a senator stepping
 * back from a bill that touches a donor's industry is the row a reader most wants to see (#154). A recusal that
 * is already among the recent bills is not repeated. `recent` is true for the capped list, false for the extras.
 */
export function overlapExamplesSql(examples: number, overlap: string): string {
  const pickPerBill = (where: string) => `
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
          from ov ${where}`;
  return `
      with ov as (select * from ${overlap}),
      recent as (
        select *, row_number() over (partition by official_id, industry order by vote_date desc, bill, session_code) as rank
        from (${pickPerBill("")}) as per_bill
        where pick = 1
      ),
      recused as (
        select * from (${pickPerBill("where vote_cast = 'recused'")}) as per_bill where pick = 1
      )
      select official_id, industry, cast(vote_date as varchar) as vote_date, bill, short_title, vote_cast,
             vote_source_url, bill_source_url, recent, chamber, vote_stage, vote_informal
      from (
        select *, true as recent from recent where rank <= ${examples}
        union all
        select r.*, null as rank, false as recent from recused as r
        where not exists (
          select 1 from recent as c
          where c.rank <= ${examples} and c.official_id = r.official_id and c.industry = r.industry
            and c.session_code = r.session_code and c.bill = r.bill and c.vote_id = r.vote_id and c.chamber = r.chamber
        )
      ) as listed
      order by official_id, industry, vote_date desc, bill, session_code`;
}

/** The Senate roll calls among a group's votes: the only ones the recused count can speak for. */
export function senateRollCallsSql(): string {
  return `cast(count(distinct case when chamber = 'state_senate' then vote_id end) as integer)`;
}

/**
 * SQL for the per (official, industry) recused count, over rpt_interest_vote_overlap rows. Only the MO Senate
 * records recusals, so a group with no state_senate vote yields null ("not recorded"), never 0 (#154).
 */
export function recusedSql(): string {
  return `case when bool_or(chamber = 'state_senate')
          then cast(count(distinct case when vote_cast = 'recused' then vote_id end) as integer) end`;
}
