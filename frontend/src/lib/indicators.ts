// What each fct_bias_indicators.indicator means and how to draw it. Shared by the profile and methodology
// pages so the explanation next to a number is always the one on the methodology page.

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

/** "Among 90 Missouri House members (2025):" lead of a peer strip's text summary */
export const peerStripLead = (peerCount: number, where: string, period: string | number | null) =>
  `Among ${plural(peerCount, `${where} member`, `${where} members`)}${period ? ` (${period})` : ""}:`;

/** the party-line "breaks" sentence on a legislator's voting section */
export const breaksText = (n: number) =>
  n === 0
    ? "No recorded votes against their party's majority on a party-line vote."
    : `${plural(n, "recorded vote", "recorded votes")} against their party's majority on a party-line vote.`;
