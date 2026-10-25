// Award badges next to an official's name. Which awards are "current" is decided here from the rpt_awards
// rows (already ranked and streak-counted in dbt); every page and browser script draws them with
// renderBadges, so the icon, the link and the accessible text are the same everywhere.
import { AWARD_PAIRS, AWARDS } from "./exports/awardDefs.ts";
import { count, money, pct, streakMarker } from "./format.ts";

/** One award an official holds now: [award key, consecutive-year streak or null, plain-language detail]. */
export type Badge = [award: string, streak: number | null, detail: string];

/** The slice of an awards list this needs (see AwardList in exports/awards.ts). */
export interface BadgeList {
  award: string;
  office: string;
  period: string;
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

/** "62.5% of 1,203 votes", the measured number with what it is out of. */
export function metricText(award: string, metric: number, sampleSize: number | null): string {
  const def = AWARDS[award];
  const value = def?.unit === "money" ? money(metric) : pct(metric);
  if (sampleSize == null || !def?.outOf) return value;
  return `${value} of ${def.outOf === "votes" ? `${count(sampleSize)} votes` : `${money(sampleSize)} raised`}`;
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

/** 1st, 2nd, 3rd, 4th, 11th, 22nd. */
export function ordinal(n: number): string {
  const tail = n % 100;
  const suffix =
    tail >= 11 && tail <= 13
      ? "th"
      : (({ 1: "st", 2: "nd", 3: "rd" } as Record<number, string>)[n % 10] ?? "th");
  return `${n}${suffix}`;
}

/**
 * Current awards by official slug. "Current" is each award's latest yearly list within each office (the
 * awards page ranks officials only against the same office), so an office whose newest year was skipped, or
 * that is only ranked lifetime, still shows its own list. An award with no yearly list for an office, such
 * as party breaks, uses that office's lifetime list. An official ranked in the same award under two offices
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
        const when = l.period === "lifetime" ? "across all loaded years" : `in ${l.period}`;
        const group = `${ordinal(e.rank)} of ${count(l.group_size)} ${officeLabel(l.office)}`;
        const detail =
          `${awardNickname(l.award)} (${lowerFirst(AWARDS[l.award]?.title ?? l.award)}), ranked ${group} ${when}: ` +
          metricText(l.award, e.metric, e.sample_size);
        mine.set(l.award, {
          rank: e.rank,
          badge: [l.award, l.period === "lifetime" ? null : e.streak_years, detail],
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
  const items = badges.map(([award, streak, detail]) => {
    const marker = streaks ? streakMarker(streak) : null;
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
