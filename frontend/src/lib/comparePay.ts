// Pay per vote attended for the compare page's rows, built from the profile's own helpers (attendancePay.ts) so
// both pages show the same numbers. Imports use .ts so node can test it directly.
import { dollars, payPerVoteBlocks, totalWithoutMedium, type PayVoteBlock } from "./attendancePay.ts";
import type { OfficialBundle } from "./exports/types";

const NA = "—";

const CHAMBER_NAMES: Record<string, string> = {
  state_house: "Missouri House",
  state_senate: "Missouri Senate",
  us_house: "U.S. House",
  us_senate: "U.S. Senate",
};

/** Years as a compact label: "2019–2024" when they run unbroken, otherwise "2019, 2021–2022". */
export function yearsLabel(years: number[]): string {
  const ys = [...new Set(years)].sort((a, b) => a - b);
  const parts: string[] = [];
  for (let i = 0; i < ys.length;) {
    let j = i;
    while (j + 1 < ys.length && ys[j + 1] === ys[j] + 1) j++;
    parts.push(j > i ? `${ys[i]}–${ys[j]}` : `${ys[i]}`);
    i = j + 1;
  }
  return parts.join(", ");
}

const basisLabel = (basis: string | null) =>
  basis === "statutory salary"
    ? "federal statutory salary"
    : basis === "gross pay"
      ? "state payroll gross pay"
      : "pay";

/**
 * Pay per vote attended, as the profile counts it (rpt_attendance_pay): the total over the years with both pay and
 * votes, and the latest calendar year with pay. Each figure names its years and pay basis. Years matched by name
 * only are marked "possible match", or left out when the reader hides them (the total is then recomputed from the
 * visible year rows, as on the profile).
 */
export function payPerVote(b: OfficialBundle, hideMedium: boolean): [string, string] {
  const blocks: PayVoteBlock[] = payPerVoteBlocks(b.voting.attendance ?? [], b.voting.attendance_pay ?? []);
  const totals: string[] = [];
  const latests: string[] = [];
  for (const block of blocks) {
    const where = blocks.length > 1 ? `${CHAMBER_NAMES[block.chamber] ?? block.chamber}: ` : "";
    const basis = basisLabel(block.basis);
    const years = block.years.filter(
      (y) => y.pay_amount != null && !(hideMedium && y.match_confidence === "medium"),
    );
    const sure = hideMedium ? totalWithoutMedium(block.years) : block.total;
    if (sure.dollars_per_vote_attended != null) {
      const flag =
        !hideMedium && block.total.match_confidence === "medium" ? "; includes possible match" : "";
      totals.push(
        `${where}${dollars(sure.dollars_per_vote_attended)} (${yearsLabel(years.map((y) => y.calendar_year!))}, ${basis}${flag})`,
      );
    }
    const last = years.filter((y) => y.dollars_per_vote_attended != null).at(-1);
    if (last) {
      const flag = last.match_confidence === "medium" ? "; possible match" : "";
      latests.push(
        `${where}${dollars(last.dollars_per_vote_attended)} (${last.calendar_year}, ${basis}${flag})`,
      );
    }
  }
  return [totals.join("; ") || NA, latests.join("; ") || NA];
}

/**
 * The payroll (or statutory salary) pages behind the pay figures, one per chamber shown, labelled with the
 * chamber when there is more than one. Chambers with no source URL are left out.
 */
export function payPerVoteSources(b: OfficialBundle): { text: string; href: string; context: string }[] {
  const blocks = payPerVoteBlocks(b.voting.attendance ?? [], b.voting.attendance_pay ?? []);
  return blocks.flatMap((block) =>
    block.sourceUrl
      ? [
          {
            text:
              blocks.length > 1
                ? `${CHAMBER_NAMES[block.chamber] ?? block.chamber} pay source`
                : "pay source",
            href: block.sourceUrl,
            // screen-reader-only, so a row of "pay source" links says whose pay each one is
            context: `for ${b.official.full_name}`,
          },
        ]
      : [],
  );
}
