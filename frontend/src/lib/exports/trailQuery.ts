/**
 * SQL for each official's top committee-donor trails. `rollup` and `donors` are table expressions
 * (`{rpt_donor_rollup}` placeholders in load.ts). Both tables have a `donor_mec_committee_id` column,
 * so every column here is qualified: an unqualified name inside the `exists` subquery binds to the
 * donor list's own column and the filter silently passes everything.
 *
 * The names the official's committee filed the donor under are a second query (one row per name, #833),
 * not a delimited string column: a name can hold any punctuation, so no separator is safe.
 */
function rankedCte(trails: number, rollup: string, donors: string): string {
  return `with ranked as (
          select dr.official_id, dr.donor_mec_committee_id as mec_committee_id,
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
        )`;
}

export function trailRowsSql(trails: number, rollup: string, donors: string): string {
  return `
        ${rankedCte(trails, rollup, donors)}
        select official_id, mec_committee_id, gave_official, first_year, last_year, link_confidence
        from ranked
        where rank <= ${trails} order by official_id, rank`;
}

/** One row per (official, shown committee, name filed), in name order with a unique tie-break. */
export function trailDonorNamesSql(trails: number, rollup: string, donors: string): string {
  return `
        ${rankedCte(trails, rollup, donors)}
        select distinct rk.official_id, rk.mec_committee_id, dr.donor_name
        from ranked as rk
        inner join ${rollup} as dr
          on dr.official_id = rk.official_id and dr.donor_mec_committee_id = rk.mec_committee_id
        where rk.rank <= ${trails} and dr.donor_name is not null
        order by rk.official_id, rk.mec_committee_id, dr.donor_name`;
}
