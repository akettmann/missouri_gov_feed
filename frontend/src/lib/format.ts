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

export const isMedium = (confidence: string | null | undefined) => confidence === "medium";

export const LEVELS: Record<string, string> = { state: "State", federal: "Federal", local: "Local" };
