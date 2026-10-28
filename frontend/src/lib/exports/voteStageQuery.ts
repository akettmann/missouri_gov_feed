/**
 * SQL for the stage of each Missouri roll call, one row per (chamber, vote_id), read from
 * fct_votes (`{fct_votes}` is a placeholder resolved by query()). fct_votes has one row per official per vote,
 * but the stage comes from the vote's own description and measure, so every row of a vote agrees; min/bool_or
 * keep the pick deterministic regardless. Join on (chamber, vote_id) only: the Senate overlap report carries the bill session code ('221') where fct_votes
 * carries the year ('2022'), so session_code never matches for the Senate; vote_id is unique per chamber.
 * Congress rows have no stage and are left out, so a federal vote joined to this finds nothing and stageLabel() shows no label for it.
 */
export function voteStagesSql(): string {
  return `select chamber, vote_id, min(vote_stage) as vote_stage, bool_or(vote_informal) as vote_informal
          from {fct_votes}
          where chamber in ('state_house', 'state_senate')
          group by chamber, vote_id`;
}
