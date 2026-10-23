const usd0 = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const usd2 = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" });
const num = new Intl.NumberFormat("en-US");

export const money = (n: number) => (Math.abs(n) >= 1000 ? usd0 : usd2).format(n);
export const count = (n: number) => num.format(n);

export function officeLine(o: { office_title: string | null; office: string; district: string | null }) {
  const title = o.office_title ?? o.office.replaceAll("_", " ");
  return o.district && !title.includes(o.district) ? `${title}, district ${o.district}` : title;
}

/** Coverage status text -> one of a few visual states (the full text is always shown too). */
export function statusKind(status: string): "available" | "none" | "not-public" | "na" {
  if (status === "available") return "available";
  if (status.startsWith("not public")) return "not-public";
  if (status === "not applicable") return "na";
  return "none";
}

/** MO House codes are two-digit year + type (1 regular, 2-4 extraordinary); Senate uses the year; Congress its number. */
export function sessionLabel(chamber: string, code: string): string {
  if (chamber.startsWith("us_")) return `${code}th Congress`;
  if (chamber === "state_house" && /^\d{3}$/.test(code)) {
    const year = `20${code.slice(0, 2)}`;
    return code[2] === "1" ? `${year} regular` : `${year} extraordinary ${Number(code[2]) - 1}`;
  }
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

/** Plain names for the roster sources behind rpt_officeholders_by_year; unknown values show as given. */
export const ROSTER_SOURCES: Record<string, string> = {
  "mo_house roster": "Missouri House roster",
  openstates: "Open States people data",
  "congress-legislators": "congress-legislators (U.S. Congress)",
  fjc: "Federal Judicial Center biographical directory",
};
