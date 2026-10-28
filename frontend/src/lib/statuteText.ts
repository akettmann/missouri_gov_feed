// Rendering rules for RSMo section pages (#840). Pure functions, no I/O, so node tests can pin them.
// The law's text is shown exactly as the Revisor of Statutes publishes it. The only structure we add is the
// Revisor's own: a blank line starts a new paragraph, a single line break stays a line break, and a line whose
// cells are tab-separated is a row of a table. Everything is escaped; no source text reaches the page as HTML.

/** One row of fct_statute_sections (with its footnotes attached by the loader). */
export interface StatuteVersion {
  section_id: string;
  bid: number;
  section_version_id: string;
  chapter: string | null;
  chapter_name: string | null;
  title_numeral: string | null;
  title_name: string | null;
  heading: string | null;
  status: string;
  is_current: boolean;
  /** ISO date (YYYY-MM-DD) or null */
  effective_date: string | null;
  held_unconstitutional: boolean;
  ended_date: string | null;
  transferred_to: string | null;
  history_note: string | null;
  section_text: string | null;
  repeal_pending: boolean;
  source_url: string | null;
  /** ISO timestamp of the pipeline's publish of the raw table, not of the fetch from revisor.mo.gov (#852) */
  loaded_at: string | null;
  footnotes: StatuteFootnote[];
}

export interface StatuteFootnote {
  footnote_number: number;
  footnote_text: string;
  is_history_note: boolean;
}

export function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

const lineHtml = (lines: string[]) => lines.map(escapeHtml).join("<br>\n");

/**
 * The section text as HTML: two or more newlines separate paragraphs, a single newline is a line break, and a
 * run of lines containing a tab is a table whose cells are the tab-separated fields. Empty or null text
 * (repealed and transferred sections have none) gives "". Text is not trimmed or reworded.
 */
export function statuteBodyHtml(text: string | null | undefined): string {
  if (!text) return "";
  const out: string[] = [];
  for (const chunk of text.split(/\n{2,}/)) {
    if (chunk === "") continue;
    let prose: string[] = [];
    let rows: string[] = [];
    const flushProse = () => {
      if (prose.length) out.push(`<p>${lineHtml(prose)}</p>`);
      prose = [];
    };
    const flushRows = () => {
      if (rows.length) out.push(`<table class="statute-table"><tbody>\n${rows.join("\n")}\n</tbody></table>`);
      rows = [];
    };
    for (const line of chunk.split("\n")) {
      if (line.includes("\t")) {
        flushProse();
        rows.push(
          `<tr>${line
            .split("\t")
            .map((c) => `<td>${escapeHtml(c)}</td>`)
            .join("")}</tr>`,
        );
      } else {
        flushRows();
        prose.push(line);
      }
    }
    flushProse();
    flushRows();
  }
  return out.join("\n");
}

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/** "2015-08-28" -> "August 28, 2015"; anything that is not an ISO date prefix is returned as is. */
export function longDate(iso: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso ?? "");
  if (!m) return iso ?? "";
  const month = MONTHS[Number(m[2]) - 1];
  return month ? `${month} ${Number(m[3])}, ${m[1]}` : (iso ?? "");
}

export interface StatusLabel {
  /** short label for the version's heading */
  label: string;
  /** a sentence that says what the label means and carries the dates */
  detail: string;
  /** set for a transferred section: the section it moved to (the page links it when it has a page) */
  transferredTo: string | null;
}

/** The Revisor's own mark for a version a court struck down in whole or in part. */
export const UNCONSTITUTIONAL_MARK = "(all or part is unconstitutional)";

type StatusInput = Pick<
  StatuteVersion,
  "status" | "is_current" | "effective_date" | "ended_date" | "transferred_to"
>;

export function statusLabel(v: StatusInput): StatusLabel {
  const eff = v.effective_date ? longDate(v.effective_date) : null;
  const end = v.ended_date ? longDate(v.ended_date) : null;
  switch (v.status) {
    case "in force":
      return v.is_current
        ? { label: "In force", detail: eff ? `In force since ${eff}.` : "In force.", transferredTo: null }
        : {
            label: "In force (earlier version)",
            detail: `An earlier version that the Revisor still prints beside the current one${eff ? `; it took effect ${eff}` : ""}.`,
            transferredTo: null,
          };
    case "not yet effective":
      return {
        label: "Not yet effective",
        detail: eff ? `Takes effect ${eff}.` : "Has not taken effect.",
        transferredTo: null,
      };
    case "contingent":
      return {
        label: "Contingent",
        detail:
          "Takes effect when an event happens, not on a set date. The Revisor gives no real date for it.",
        transferredTo: null,
      };
    case "repealed":
      return {
        label: "Repealed",
        detail: end ? `Repealed ${end}.` : "Repealed; the Revisor gives no date.",
        transferredTo: null,
      };
    case "transferred":
      return {
        label: "Transferred",
        detail: `${end ? `Transferred ${end}` : "Transferred"}${v.transferred_to ? ` to section ${v.transferred_to}` : ""}.`,
        transferredTo: v.transferred_to,
      };
    case "historical":
      return {
        label: "Historical",
        detail: `An expired version that the Revisor still prints${eff ? `; it took effect ${eff}` : ""}.`,
        transferredTo: null,
      };
    default:
      return { label: v.status, detail: "", transferredTo: null };
  }
}

const GROUP: Record<string, number> = {
  "not yet effective": 1,
  contingent: 2,
  "in force": 3,
  historical: 3,
  repealed: 4,
  transferred: 4,
};

/**
 * Display order for one section's versions: the current version(s) first, then not yet effective, contingent,
 * earlier in-force and historical, and repeal/transfer notes last; within a group the newest effective date
 * first, and the Revisor's version id (bid), unique within a section, breaks every remaining tie.
 */
export function orderVersions<
  T extends Pick<StatuteVersion, "status" | "is_current" | "effective_date" | "bid">,
>(versions: readonly T[]): T[] {
  const rank = (v: T) => (v.is_current ? 0 : (GROUP[v.status] ?? 5));
  return versions.toSorted(
    (a, b) =>
      rank(a) - rank(b) || (b.effective_date ?? "").localeCompare(a.effective_date ?? "") || a.bid - b.bid,
  );
}

export const footnotesInOrder = (fs: readonly StatuteFootnote[]): StatuteFootnote[] =>
  fs.toSorted((a, b) => a.footnote_number - b.footnote_number);

/**
 * The "as of" sentence. loaded_at is when our pipeline published the raw table, not when the Revisor's page
 * was fetched (the page can be up to 180 days older; #852), so it is worded as exactly that.
 */
export function asOfText(loadedAt: string | null | undefined): string {
  const when = loadedAt ? longDate(loadedAt) : null;
  return (
    (when ? `Our pipeline published this page's data on ${when}. ` : "") +
    "The Revisor's page may have been fetched up to 180 days before that, and the Revisor may have changed it since. " +
    "Check the Revisor's page for the current law."
  );
}

/** Path (no base) of a section's page; ids use only letters, digits, dots and hyphens, so no encoding is needed. */
export const statutePath = (sectionId: string): string => `/statutes/${sectionId}/`;
