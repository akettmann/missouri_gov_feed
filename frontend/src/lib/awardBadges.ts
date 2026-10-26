// Award badges next to an official's name. Which awards are "current" is decided here from the rpt_awards
// rows (already ranked and streak-counted in dbt); every page and browser script draws them with
// renderBadges, so the icon, the link and the accessible text are the same everywhere.
import { AWARD_PAIRS, AWARDS, isCycleList, periodWhen, type PeriodKind } from "./exports/awardDefs.ts";
import { count, money, ordinal, pct, plural, streakMarker } from "./format.ts";

// ordinal lives in format.ts (sessionLabel needs it too); re-exported for existing importers.
export { ordinal };

/**
 * One award an official holds now: [award key, consecutive-period streak or null, plain-language detail,
 * whether the periods are two-year FEC cycles rather than calendar years].
 */
export type Badge = [award: string, streak: number | null, detail: string, cycle?: boolean];

/** The slice of an awards list this needs (see AwardList in exports/awards.ts). */
export interface BadgeList {
  award: string;
  office: string;
  period: string;
  period_kind: PeriodKind;
  group_size: number;
  entries: {
    rank: number;
    slug: string;
    metric: number;
    sample_size: number | null;
    streak_years: number | null;
  }[];
}

/**
 * Placeholder art: one plain glyph per award key, all drawn the same way for every official. Swap the real
 * icons in here; nothing else knows what they look like.
 */
export const AWARD_ICONS: Record<string, string> = {
  lowest_attendance: "▽",
  highest_attendance: "△",
  most_committee_money: "$",
  least_committee_money_share: "%",
  most_party_breaks: "↯",
  most_party_loyal: "=",
};
const FALLBACK_ICON = "★";

const ORDER = AWARD_PAIRS.flat();
const orderOf = (award: string) => {
  const i = ORDER.indexOf(award);
  return i < 0 ? ORDER.length : i;
};

/**
 * What the number rests on, after the number: "of 1,203 votes", "of $5,000 raised", "with party, of 26 party-line votes".
 * The party awards rank unity (the share cast with the official's own party), so they read "with party, of N party-line votes".
 */
export function outOfText(award: string, sampleSize: number | null): string {
  const outOf = AWARDS[award]?.outOf;
  if (sampleSize == null || !outOf) return "";
  if (outOf === "votes") return `of ${plural(sampleSize, "vote", "votes")}`;
  if (outOf === "raised") return `of ${money(sampleSize)} raised`;
  return `with party, of ${plural(sampleSize, "party-line vote", "party-line votes")}`;
}

/** "62.5% of 1,203 votes", the measured number with what it is out of. */
export function metricText(award: string, metric: number, sampleSize: number | null): string {
  const value = AWARDS[award]?.unit === "money" ? money(metric) : pct(metric);
  const out = outOfText(award, sampleSize);
  return out ? `${value} ${out}` : value;
}

/** "Never Misses a Vote": the award's nickname without the "The ... Award" wrapper and curly quotes. */
export function awardNickname(award: string): string {
  const name = AWARDS[award]?.name ?? award;
  return name
    .replace(/^The\s+/, "")
    .replace(/\s+Award$/, "")
    .replace(/[“”"]/g, "");
}

/** Lower-case the first letter only, so "PACs" stays "PACs". */
const lowerFirst = (s: string) => s.charAt(0).toLowerCase() + s.slice(1);

/**
 * Current awards by official slug. "Current" is each award's latest yearly list within each office (the
 * awards page ranks officials only against the same office), so an office whose newest year was skipped, or
 * that is only ranked lifetime, still shows its own list. An award with no yearly list for an office
 * uses that office's lifetime list. An official ranked in the same award under two offices
 * keeps the better rank. Order is the awards page's. `officeLabel` turns an office key into the plural name
 * of its holders for the badge text ("State Representatives", as the awards page writes it).
 */
export function currentAwards(
  lists: BadgeList[],
  officeLabel: (office: string) => string = (o) => o,
): Map<string, Badge[]> {
  const key = (l: BadgeList) => `${l.award}|${l.office}`;
  const latest = new Map<string, string>();
  for (const l of lists)
    if (l.period !== "lifetime" && l.period > (latest.get(key(l)) ?? "")) latest.set(key(l), l.period);
  const current = lists.filter((l) => l.period === (latest.get(key(l)) ?? "lifetime"));
  const best = new Map<string, Map<string, { rank: number; badge: Badge }>>();
  for (const l of current)
    for (const e of l.entries) {
      const mine = best.get(e.slug) ?? new Map<string, { rank: number; badge: Badge }>();
      const had = mine.get(l.award);
      if (!had || e.rank < had.rank) {
        const cycle = isCycleList(l);
        const when = periodWhen(l.period, cycle);
        const group = `${ordinal(e.rank)} of ${count(l.group_size)} ${officeLabel(l.office)}`;
        const detail =
          `${awardNickname(l.award)} (${lowerFirst(AWARDS[l.award]?.title ?? l.award)}), ranked ${group} ${when}: ` +
          metricText(l.award, e.metric, e.sample_size);
        mine.set(l.award, {
          rank: e.rank,
          badge: [l.award, l.period === "lifetime" ? null : e.streak_years, detail, cycle],
        });
      }
      best.set(e.slug, mine);
    }
  return new Map(
    [...best].map(([slug, mine]) => [
      slug,
      [...mine].sort(([a], [b]) => orderOf(a) - orderOf(b) || a.localeCompare(b)).map(([, v]) => v.badge),
    ]),
  );
}

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/**
 * The badges as HTML (empty string for none). Each icon links to the award's explanation on /awards. The
 * visible glyph and streak marker are aria-hidden; the same words are .sr-only text, because aria-label
 * isn't allowed on a generic element. `streaks: false` leaves the X2/X3 off where the page shows its own.
 */
export function renderBadges(badges: Badge[], base: string, streaks = true): string {
  if (badges.length === 0) return "";
  const items = badges.map(([award, streak, detail, cycle]) => {
    const marker = streaks ? streakMarker(streak, cycle === true) : null;
    const spoken = `Award: ${detail}${marker ? `; ${marker.label}` : ""}`;
    return (
      `<a class="award-badge" href="${esc(`${base}/awards/#${award}`)}" title="${esc(spoken)}">` +
      `<span class="award-icon" aria-hidden="true">${AWARD_ICONS[award] ?? FALLBACK_ICON}</span>` +
      (marker ? `<span class="award-streak" aria-hidden="true">${esc(marker.text)}</span>` : "") +
      `<span class="sr-only">${esc(spoken)}</span></a>`
    );
  });
  return `<span class="award-badges">${items.join("")}</span>`;
}

/**
 * Plural group label for each office key in the exports. An office's ranking group is statewide, so the label
 * must not carry a per-person qualifier (a circuit number or district) that dim_official.office_title has.
 */
export const OFFICE_GROUP_LABELS: Record<string, string> = {
  state_house: "State Representatives",
  state_senate: "State Senators",
  us_house: "U.S. Representatives",
  us_senate: "U.S. Senators",
  mo_circuit_judge: "Circuit Judges",
  mo_associate_circuit_judge: "Associate Circuit Judges",
  mo_court_of_appeals: "Court of Appeals Judges",
  mo_supreme_court: "Supreme Court Judges",
  us_district_court: "U.S. District Court Judges",
  us_court_of_appeals: "U.S. Court of Appeals Judges",
  state_treasurer: "State Treasurers",
  attorney_general: "Attorneys General",
  lt_governor: "Lieutenant Governors",
  governor: "Governors",
  secretary_of_state: "Secretaries of State",
  state_auditor: "State Auditors",
  mayor: "Mayors",
};

const warnedOffices = new Set<string>();

/**
 * Plural label for an office key. A key missing from OFFICE_GROUP_LABELS is labelled from the key's words only
 * ("county_clerk" -> "County Clerks"), never from a holder's title, which would name one holder's seat (a
 * mayor's city, a judge's circuit). The pluralizer is crude on purpose ("appeals_east" -> "Appeals Easts"); add
 * the key to OFFICE_GROUP_LABELS instead. Warns once per unmapped key so a build surfaces new keys.
 */
export function pluralOfficeLabel(office: string): string {
  const known = OFFICE_GROUP_LABELS[office];
  if (known) return known;
  if (!warnedOffices.has(office)) {
    warnedOffices.add(office);
    console.warn(`office key "${office}" has no entry in OFFICE_GROUP_LABELS; labelling it from the key`);
  }
  const base = office.replaceAll("_", " ").replace(/\b[a-z]/g, (c) => c.toUpperCase());
  return base.endsWith("s") ? base : `${base}s`;
}

/** Singular tab label for an office key (the plural minus its group "s"), for headings. */
export function singularOfficeLabel(office: string): string {
  return pluralOfficeLabel(office)
    .replace(/^Attorneys General$/, "Attorney General")
    .replace(/^Secretaries of State$/, "Secretary of State")
    .replace(/s$/, "");
}
