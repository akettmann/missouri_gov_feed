// Row selection for the "Pay per vote attended" table under the attendance chart (no imports, so node can test
// it directly). The division happens in dbt (rpt_attendance_pay); this only picks the rows that cover the same
// sessions the attendance chart shows, in the chart's chamber order, and words their coverage.

export interface PayVoteRow {
  chamber: string;
  /** a calendar year such as "2021", or "covered years" for the total over years with both pay and votes */
  period: string;
  calendar_year: number | null;
  voting_years: number;
  covered_years: number;
  votes_recorded: number;
  votes_attended: number;
  pay_amount: number | null;
  pay_basis: string | null;
  pay_source_url: string | null;
  /** lowest match_confidence of the payroll rows behind pay_amount; "medium" = matched by name only */
  match_confidence: string | null;
  dollars_per_vote_attended: number | null;
}

export interface PayVoteBlock {
  chamber: string;
  /** one row per calendar year the chart's sessions for this chamber have votes in, oldest first */
  years: PayVoteRow[];
  /** the total over the years that have both pay and votes */
  total: PayVoteRow;
  /** 'gross pay' (state payroll) or 'statutory salary' (Congress) */
  basis: string | null;
  sourceUrl: string | null;
}

export const TOTAL_PERIOD = "covered years";

const yearOf = (date: string | null) => (date ? Number(date.slice(0, 4)) : null);

/**
 * The pay-per-vote blocks for the sessions in `attendance`: one block per chamber shown in the chart, with a
 * row for each calendar year those sessions have votes in. Years outside the chart's sessions are dropped, so
 * the table can never show a range the chart does not. A chamber with no year of pay gets no block.
 */
export function payPerVoteBlocks(
  attendance: { chamber: string; first_vote_date: string | null; last_vote_date: string | null }[],
  pay: PayVoteRow[],
): PayVoteBlock[] {
  const shown = new Map<string, Set<number>>();
  for (const a of attendance) {
    const first = yearOf(a.first_vote_date);
    const last = yearOf(a.last_vote_date);
    if (first == null || last == null) continue;
    const years = shown.get(a.chamber) ?? new Set<number>();
    for (let y = first; y <= last; y++) years.add(y);
    shown.set(a.chamber, years);
  }
  const blocks: PayVoteBlock[] = [];
  for (const [chamber, years] of shown) {
    const mine = pay.filter((p) => p.chamber === chamber);
    const total = mine.find((p) => p.period === TOTAL_PERIOD);
    if (!total) continue;
    const rows = mine
      .filter((p) => p.period !== TOTAL_PERIOD && p.calendar_year != null && years.has(p.calendar_year))
      .sort((a, b) => a.calendar_year! - b.calendar_year!);
    const withPay = rows.find((r) => r.pay_amount != null);
    blocks.push({
      chamber,
      years: rows,
      total,
      basis: withPay?.pay_basis ?? total.pay_basis,
      sourceUrl: withPay?.pay_source_url ?? total.pay_source_url,
    });
  }
  return blocks;
}

/**
 * Why the block's year rows do not add up to its dbt total, or null when they do. The total is computed over every
 * year in fct_votes while the rows are cut to the chart's sessions (rpt_attendance), so a stale export of either
 * makes a label like "2023–2025" sit on a figure that covers 2021–2025. Checks that the rows are one per year
 * with votes (total.voting_years) and that the years with pay among them are total.covered_years.
 */
export function payYearsMismatch(block: PayVoteBlock): string | null {
  const withPay = block.years.filter((y) => y.pay_amount != null).length;
  if (block.years.length === block.total.voting_years && withPay === block.total.covered_years) return null;
  return (
    `${block.chamber}: ${block.years.length} year rows (${withPay} with pay) but the total covers ` +
    `${block.total.covered_years} of ${block.total.voting_years} years`
  );
}

/** One message per official whose pay year rows do not add up to the total, naming the official. */
export function payYearsProblems(
  bundles: {
    official: { full_name: string; official_id: string };
    voting: {
      attendance: { chamber: string; first_vote_date: string | null; last_vote_date: string | null }[] | null;
      attendance_pay: PayVoteRow[] | null;
    };
  }[],
): string[] {
  const out: string[] = [];
  for (const b of bundles) {
    for (const block of payPerVoteBlocks(b.voting.attendance ?? [], b.voting.attendance_pay ?? [])) {
      const why = payYearsMismatch(block);
      if (why) out.push(`${b.official.full_name} (${b.official.official_id}) ${why}`);
    }
  }
  return out;
}

/**
 * The total again with the "possible match" years left out, for when the reader hides medium matches: the
 * sums are recomputed from the visible year rows, never taken from the (medium-inclusive) dbt total.
 */
export function totalWithoutMedium(
  years: PayVoteRow[],
): Pick<
  PayVoteRow,
  "voting_years" | "covered_years" | "pay_amount" | "votes_attended" | "dollars_per_vote_attended"
> {
  const shown = years.filter((y) => y.match_confidence !== "medium");
  const covered = shown.filter((y) => y.pay_amount != null);
  const pay = covered.reduce((n, y) => n + (y.pay_amount ?? 0), 0);
  const votes = covered.reduce((n, y) => n + y.votes_attended, 0);
  return {
    // all years with votes, so the coverage note still reads "0 of 4" when the possible matches are hidden
    voting_years: years.length,
    covered_years: covered.length,
    pay_amount: covered.length ? pay : null,
    votes_attended: votes,
    dollars_per_vote_attended: covered.length && votes > 0 ? Math.round((pay / votes) * 100) / 100 : null,
  };
}

const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });

/** Whole dollars, or an em dash when there is no figure (no pay row, or no attended vote). */
export const dollars = (n: number | null | undefined) => (n == null ? "—" : usd.format(n));

/**
 * What the total covers, e.g. "2 of 4 years with votes (the rest have no pay counted)". `hidesPossible` is set for
 * the total without possible matches, whose leftover years may also be ones hidden as a name-only match.
 */
export function coverageNote(
  total: Pick<PayVoteRow, "covered_years" | "voting_years">,
  hidesPossible = false,
): string {
  const { covered_years: c, voting_years: v } = total;
  const years = (n: number) => `${n} ${n === 1 ? "year" : "years"}`;
  if (c >= v) return v === 1 ? "the 1 year with votes" : `all ${v} years with votes`;
  const rest = hidesPossible ? "no pay counted or only a possible match" : "no pay counted";
  return `${c} of ${years(v)} with votes (the rest have ${rest})`;
}

/** The pay basis in plain words, for the table's note. */
export function payBasisText(basis: string | null): string {
  if (basis === "statutory salary")
    return "the statutory annual salary of the office (federal pay is not published per person)";
  if (basis === "gross pay") return "gross pay from the state payroll (everything paid in the calendar year)";
  return "pay";
}
