// Plain-words labels for the stage of a Missouri roll call (fct_votes.vote_stage, #804). The stage says what
// kind of question the roll call decided, so a reader can tell final passage from a consent-calendar bill, an
// amendment or a procedural motion. It is a label only: no count, score or award reads it.

const STAGE_LABELS: Record<string, string> = {
  perfection: "Perfection",
  third_reading: "Third reading",
  third_reading_consent: "Consent calendar, third reading",
  senate_amendments: "Senate amendments",
  conference: "Conference report",
  veto_override: "Veto override",
  amendment: "Amendment",
  emergency_clause: "Emergency clause",
  previous_question: "Previous question",
  procedural_motion: "Procedural motion",
  quorum: "Quorum call",
  resolution: "Resolution",
  other: "Other question",
  unknown: "Stage not identified",
};

const MISSOURI_CHAMBERS = new Set(["state_house", "state_senate"]);

/** The marker a House calendar item carries when the bill sits on the informal calendar. */
export const INFORMAL_LABEL = "informal calendar";

/**
 * The label to show for a roll call, or null when none should be: a federal vote keeps Voteview's own
 * description and never gets a stage. A Missouri vote whose stage is missing or unmatched says so, never a guess.
 */
export function stageLabel(chamber: string, stage: string | null, informal: boolean | null): string | null {
  if (!MISSOURI_CHAMBERS.has(chamber)) return null;
  const base = STAGE_LABELS[stage ?? "unknown"] ?? STAGE_LABELS.unknown;
  return informal === true ? `${base} (${INFORMAL_LABEL})` : base;
}
