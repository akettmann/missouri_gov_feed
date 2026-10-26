// What each fct_bias_indicators.indicator means and how to draw it. Shared by the profile and methodology
// pages so the explanation next to a number is always the one on the methodology page.

import { ordinal } from "./awardBadges.ts";
import { plural } from "./format.ts";

export interface IndicatorMeta {
  label: string;
  /** scale drawn under the value; diverging scales get a neutral midpoint */
  domain: [number, number];
  diverging: boolean;
  low: string;
  high: string;
  meaning: string;
  limits: string;
  source: string;
}

export const INDICATORS: Record<string, IndicatorMeta> = {
  dw_nominate_dim1: {
    label: "DW-NOMINATE, first dimension",
    domain: [-1, 1],
    diverging: true,
    low: "more liberal",
    high: "more conservative",
    meaning:
      "Voteview's estimate of where a member of Congress sits on the main left-right (largely economic) " +
      "dimension, recovered from every recorded roll-call vote. Period is the Congress number.",
    limits:
      "Relative to colleagues in Congress, not to voters. Built only from votes taken, so issues that never " +
      "reach a roll call are invisible.",
    source: "Voteview (UCLA)",
  },
  shor_mccarty_np: {
    label: "Shor-McCarty ideal point",
    domain: [-2.5, 2.5],
    diverging: true,
    low: "more liberal",
    high: "more conservative",
    meaning:
      "A state legislator's career ideology score from roll-call votes, bridged across states with " +
      "candidate surveys so it is comparable nationally. Period is the last year served in the data.",
    limits: "Covers 1993-2022 only, and one score per career; recent shifts don't show up.",
    source: "Shor & McCarty, Harvard Dataverse",
  },
  party_unity_pct: {
    label: "Party unity",
    domain: [0, 100],
    diverging: false,
    low: "%",
    high: "%",
    meaning:
      "Of the party-line votes in our data (a majority of Republicans opposed a majority of Democrats), " +
      "the share where the official voted with their own party's majority.",
    limits:
      "Computed over all loaded votes; the Maverick and Team Player awards also rank each calendar year. High unity is the norm in every legislature; it " +
      "measures party alignment, not ideology.",
    source: "Computed from roll calls in this dataset",
  },
};

export function indicatorMeta(key: string): IndicatorMeta {
  return (
    INDICATORS[key] ?? {
      label: key,
      domain: [0, 1],
      diverging: false,
      low: "",
      high: "",
      meaning: "",
      limits: "",
      source: "",
    }
  );
}

/**
 * Who a peer strip counts. Every peer set is current officials only (dim_official), of any office, so the state
 * nouns name the chamber where the measurement was taken, never the office: a "Missouri House" group can
 * include a current senator or the auditor who once served there.
 */
const PEER_NOUNS: Record<string, [string, string]> = {
  state_house: ["current official", "current officials"],
  state_senate: ["current official", "current officials"],
  us_house: ["current Missouri U.S. House member", "current Missouri U.S. House members"],
  us_senate: ["current Missouri U.S. senator", "current Missouri U.S. senators"],
};

const MEASURED_IN: Record<string, string> = {
  state_house: "the Missouri House",
  state_senate: "the Missouri Senate",
  us_house: "the U.S. House",
  us_senate: "the U.S. Senate",
};

/**
 * "Among 2 current Missouri U.S. senators with a score in the 119th Congress:" lead of a peer strip's text summary.
 * Peers are current officials grouped by the chamber of the measurement. `period` is a Congress number for
 * DW-NOMINATE (the peers share that Congress); Shor-McCarty groups by the chamber of each official's last
 * Shor-McCarty score (period is only the last year served), and party unity by the chamber whose loaded
 * party-line votes they cast; so only DW-NOMINATE names the period.
 */
export const peerStripLead = (
  peerCount: number,
  chamber: string,
  indicator: string,
  period: number | null,
) => {
  const [one, many] = PEER_NOUNS[chamber] ?? [`${chamber} member`, `${chamber} members`];
  const where = MEASURED_IN[chamber] ?? chamber;
  const who = plural(peerCount, one, many);
  if (indicator === "dw_nominate_dim1") {
    return `Among ${who} with a score${period == null ? "" : ` in the ${ordinal(period)} Congress`}:`;
  }
  if (indicator === "shor_mccarty_np") {
    return `Among ${who} whose Shor-McCarty career score was last measured in ${where}:`;
  }
  return `Among ${who} who cast party-line votes in ${where}:`;
};

/** the party-line "breaks" sentence on a legislator's voting section */
export const breaksText = (n: number) =>
  n === 0
    ? "No recorded votes against their party's majority on a party-line vote."
    : `${plural(n, "recorded vote", "recorded votes")} against their party's majority on a party-line vote.`;

const CHAMBER_NAMES: Record<string, string> = {
  state_house: "Missouri House",
  state_senate: "Missouri Senate",
  us_house: "U.S. House",
  us_senate: "U.S. Senate",
};

/**
 * Reader-facing text for a fct_bias_indicators `detail`. The raw detail stays the internal match key (peer strips,
 * current-chamber ordering); only display goes through here. Handles every shape the mart emits:
 *   "state_house: 1006 party-line votes"                      -> "1,006 party-line votes cast in the Missouri House"
 *   "Voteview DW-NOMINATE, House 119th Congress"              -> "Voteview DW-NOMINATE, U.S. House, 119th Congress"
 *   "Shor-McCarty career ideal point; served 2009-2022"       -> "... served 2009–2022"
 * The Congress ordinal is taken as written (never re-derived), so "121st" survives. Unknown shapes pass through.
 */
export function indicatorDetailText(detail: string | null | undefined): string {
  if (!detail) return "";
  const unity = /^(\w+): (\d+) party-line votes?$/.exec(detail);
  if (unity) {
    const n = Number(unity[2]);
    const where = CHAMBER_NAMES[unity[1]] ?? unity[1];
    return `${plural(n, "party-line vote", "party-line votes")} cast in the ${where}`;
  }
  const dw = /^(.*DW-NOMINATE), (House|Senate) (\S+ Congress)$/.exec(detail);
  if (dw) return `${dw[1]}, U.S. ${dw[2]}, ${dw[3]}`;
  const sm = /^(.*; served )(\d{4})-(\d{4})$/.exec(detail);
  if (sm) return `${sm[1]}${sm[2]}–${sm[3]}`;
  return detail;
}
