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

/** Who a peer strip counts: the Missouri officials tracked here, not the whole chamber. */
const PEER_NOUNS: Record<string, [string, string]> = {
  state_house: ["Missouri House member", "Missouri House members"],
  state_senate: ["Missouri Senate member", "Missouri Senate members"],
  us_house: ["Missouri U.S. House member", "Missouri U.S. House members"],
  us_senate: ["Missouri U.S. senator", "Missouri U.S. senators"],
};

/**
 * "Among 2 Missouri U.S. senators with a score in the 119th Congress:" lead of a peer strip's text summary.
 * `period` is a Congress number for DW-NOMINATE (the peers share that Congress) but only the last year served
 * for Shor-McCarty, whose peers are every career score in the chamber, and null for party unity (all loaded
 * votes); so only DW-NOMINATE names the period.
 */
export const peerStripLead = (
  peerCount: number,
  chamber: string,
  indicator: string,
  period: number | null,
) => {
  const [one, many] = PEER_NOUNS[chamber] ?? [`${chamber} member`, `${chamber} members`];
  const scope =
    indicator === "dw_nominate_dim1"
      ? period == null
        ? "with a score"
        : `with a score in the ${ordinal(period)} Congress`
      : indicator === "shor_mccarty_np"
        ? "with a career score"
        : "with a party-unity score";
  return `Among ${plural(peerCount, one, many)} ${scope}:`;
};

/** the party-line "breaks" sentence on a legislator's voting section */
export const breaksText = (n: number) =>
  n === 0
    ? "No recorded votes against their party's majority on a party-line vote."
    : `${plural(n, "recorded vote", "recorded votes")} against their party's majority on a party-line vote.`;
