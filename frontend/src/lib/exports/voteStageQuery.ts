/**
 * SQL for the stage of each Missouri roll call, one row per (chamber, session_code, vote_id), read from
 * fct_votes (`{fct_votes}` is a placeholder resolved by query()). fct_votes has one row per official per vote,
 * but the stage comes from the vote's own description and measure, so every row of a vote agrees; min/bool_or
 * keep the pick deterministic regardless. Congress rows have no stage and are left out, so a federal vote
 * joined to this finds nothing and stageLabel() shows no label for it.
 */
export function voteStagesSql(): string {
  return `select chamber, session_code, vote_id, min(vote_stage) as vote_stage, bool_or(vote_informal) as vote_informal
          from {fct_votes}
          where chamber in ('state_house', 'state_senate')
          group by chamber, session_code, vote_id`;
}
