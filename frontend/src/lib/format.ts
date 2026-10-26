const usd0 = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const usd2 = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });
const num = new Intl.NumberFormat("en-US");

export const money = (n: number) => (Math.abs(n) >= 1000 ? usd0 : usd2).format(n);
export const count = (n: number) => num.format(n);

/** "1 case" / "2 cases", with thousands separators: use for any count followed by a noun. */
export const plural = (n: number, one: string, many: string) => `${count(n)} ${n === 1 ? one : many}`;

/** Federal courts: `district` holds a court key (moed, mowd, ca8), and the title already names the court. */
const COURT_OFFICES = ["us_district_court", "us_court_of_appeals"];

export function officeLine(o: { office_title: string | null; office: string; district: string | null }) {
  const title = o.office_title ?? o.office.replaceAll("_", " ");
  if (COURT_OFFICES.includes(o.office)) return title;
  return o.district && !title.includes(o.district) ? `${title}, district ${o.district}` : title;
}

/** Coverage status text -> one of a few visual states (the full text is always shown too). */
export function statusKind(status: string): "available" | "none" | "not-public" | "na" {
  if (status === "available") return "available";
  if (status.startsWith("not public")) return "not-public";
  if (status === "not applicable") return "na";
  return "none";
}

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
 * The one session label. A House session is named by the House itself (dim_house_session: "2025 1st
 * Extraordinary Session", "2018 Special Session"), because the numbering of its extraordinary sessions is
 * irregular and no rule on the code works. When the name is missing the label says so ("session code 261")
 * rather than guessing a number. The Senate's session is its year; Congress its number.
 */
export function sessionLabel(chamber: string, code: string, houseName?: string | null): string {
  if (chamber.startsWith("us_")) return `${ordinal(Number(code))} Congress`;
  if (chamber === "state_house") return houseName || `session code ${code}`;
  return code;
}

export const pct = (n: number | null | undefined, digits = 1) => (n == null ? "—" : `${n.toFixed(digits)}%`);

/**
 * Coverage categories shown only where an official actually has data. Disclosures and business ties exist for
 * federal officials only; for everyone else they'd be a row of "not public", so they're hidden instead.
 */
export const HIDE_UNLESS_AVAILABLE = ["disclosures", "commercial_ties"];
export const visibleCoverage = <T extends { key: string; status: string }>(items: T[]) =>
  items.filter((c) => !HIDE_UNLESS_AVAILABLE.includes(c.key) || statusKind(c.status) === "available");

export const isMedium = (confidence: string | null | undefined) => confidence === "medium";

export const LEVELS: Record<string, string> = { state: "State", federal: "Federal", local: "Local" };

/**
 * Office tiles on the browse page. Each groups related offices (office key -> label); an office missing here
 * falls into "other", so a newly tracked office still shows up.
 */
export const OFFICE_GROUPS: { key: string; label: string; offices: Record<string, string> }[] = [
  {
    key: "legislature",
    label: "Missouri legislature",
    offices: { state_house: "Missouri House", state_senate: "Missouri Senate" },
  },
  {
    key: "statewide",
    label: "Statewide offices",
    offices: {
      governor: "Governor",
      lt_governor: "Lieutenant Governor",
      attorney_general: "Attorney General",
      secretary_of_state: "Secretary of State",
      state_auditor: "State Auditor",
      state_treasurer: "State Treasurer",
    },
  },
  {
    key: "state_courts",
    label: "Missouri courts",
    offices: {
      mo_supreme_court: "Supreme Court of Missouri",
      mo_court_of_appeals: "Missouri Court of Appeals",
      mo_circuit_judge: "Circuit judges",
      mo_associate_circuit_judge: "Associate circuit judges",
    },
  },
  { key: "congress", label: "Congress", offices: { us_senate: "U.S. Senate", us_house: "U.S. House" } },
  {
    key: "federal_courts",
    label: "Federal courts",
    offices: {
      us_court_of_appeals: "U.S. Court of Appeals, 8th Circuit",
      us_district_court: "U.S. District Courts",
    },
  },
  { key: "mayors", label: "Mayors", offices: { mayor: "Mayors" } },
];

export const officeGroup = (office: string) => OFFICE_GROUPS.find((g) => office in g.offices)?.key ?? "other";

/** [2017, 2018, 2020] -> "2017–2018, 2020": consecutive years collapse into a range. */
export function yearRanges(years: number[]): string {
  const out: string[] = [];
  const sorted = [...new Set(years)].sort((a, b) => a - b);
  for (let i = 0; i < sorted.length;) {
    let j = i;
    while (j + 1 < sorted.length && sorted[j + 1] === sorted[j] + 1) j++;
    out.push(j > i ? `${sorted[i]}–${sorted[j]}` : String(sorted[i]));
    i = j + 1;
  }
  return out.join(", ");
}

/**
 * Streak marker for an award: "X3" with a spoken label "3 qualifying years in a row" (or "3 qualifying cycles
 * in a row" when the streak counts two-year FEC cycles); null below 2 (no marker).
 */
export function streakMarker(
  years: number | null | undefined,
  cycles = false,
): { text: string; label: string } | null {
  if (years == null || years < 2) return null;
  return { text: `X${years}`, label: `${years} qualifying ${cycles ? "cycles" : "years"} in a row` };
}

/** Plain names for the roster sources behind rpt_officeholders_by_year; unknown values show as given. */
export const ROSTER_SOURCES: Record<string, string> = {
  "mo_house roster": "Missouri House roster",
  openstates: "Open States people data",
  "congress-legislators": "congress-legislators (U.S. Congress)",
  fjc: "Federal Judicial Center biographical directory",
};

/** Roster links that download a file rather than open a page, so the reader is told before clicking. */
export function rosterDownloadNote(source: string, links: number): string | null {
  if (source !== "mo_house roster") return null;
  return links > 1
    ? "each year is a ZIP download (2-3 MB) of that session's XML"
    : "the link is a ZIP download (2-3 MB) of that session's XML";
}
