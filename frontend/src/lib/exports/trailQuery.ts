/**
 * SQL for each official's top committee-donor trails. `rollup` and `donors` are table expressions
 * (`{rpt_donor_rollup}` placeholders in load.ts). Both tables have a `donor_mec_committee_id` column,
 * so every column here is qualified: an unqualified name inside the `exists` subquery binds to the
 * donor list's own column and the filter silently passes everything.
 */
export function trailRowsSql(trails: number, rollup: string, donors: string): string {
  return `
        select official_id, mec_committee_id, donor_names, gave_official, first_year, last_year, link_confidence
        from (
          select dr.official_id, dr.donor_mec_committee_id as mec_committee_id,
                 string_agg(distinct dr.donor_name, '; ' order by dr.donor_name) as donor_names,
                 cast(sum(dr.total_amount) as double) as gave_official,
                 cast(min(dr.transaction_year) as integer) as first_year,
                 cast(max(dr.transaction_year) as integer) as last_year,
                 -- 'high' < 'medium': the weakest link among the rows shown
                 max(dr.donor_link_confidence) as link_confidence,
                 row_number() over (
                   partition by dr.official_id order by sum(dr.total_amount) desc, dr.donor_mec_committee_id
                 ) as rank
          from ${rollup} as dr
          where dr.donor_mec_committee_id is not null
            -- rank only committees that have a donor list to show, so the top ${trails} are all displayable
            and exists (
              select 1 from ${donors} as cd where cd.mec_committee_id = dr.donor_mec_committee_id
            )
          group by dr.official_id, dr.donor_mec_committee_id
        ) ranked
        where rank <= ${trails} order by official_id, rank`;
}
