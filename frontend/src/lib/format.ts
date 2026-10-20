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
