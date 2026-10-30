// Rendering rules for RSMo section pages (#840). Pure functions, no I/O, so node tests can pin them.
// The law's text is shown exactly as the Revisor of Statutes publishes it. The only structure we add is the
// Revisor's own: a blank line starts a new paragraph, a single line break stays a line break, and a line whose
// cells are tab-separated is a row of a table. Everything is escaped; no source text reaches the page as HTML.
import { count, plural } from "./format.ts";

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
      if (rows.length) {
        out.push(
          `<div class="statute-table-wrap" tabindex="0" role="region" aria-label="Table in the statute text">` +
            `<table class="statute-table"><tbody>\n${rows.join("\n")}\n</tbody></table></div>`,
        );
      }
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

/** Slug of the one placeholder page built when the statute exports are missing. */
export const NOT_LOADED = "not-loaded";

/** Path (no base) of a chapter's list of sections (#841). Chapter numbers are digits with an optional letter. */
export const statuteChapterPath = (chapter: string): string => `/statutes/chapter/${chapter}/`;

/** Anchor on /statutes/ for a title ("XXVI" -> "title-xxvi"), or for the chapters the Revisor no longer lists. */
export const titleAnchor = (numeral: string | null): string =>
  numeral ? `title-${numeral.toLowerCase()}` : "no-longer-listed";

/** The Revisor's page for one chapter. */
export const revisorChapterUrl = (chapter: string): string =>
  `https://revisor.mo.gov/main/OneChapter.aspx?chapter=${encodeURIComponent(chapter)}`;

const ROMAN: Record<string, number> = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 };

/** "XXXIV" -> 34; anything that is not a roman numeral -> NaN. */
export function romanValue(numeral: string): number {
  const s = numeral.toUpperCase();
  if (!/^[IVXLCDM]+$/.test(s)) return NaN;
  let total = 0;
  for (let i = 0; i < s.length; i++) {
    const v = ROMAN[s[i]!]!;
    const next = ROMAN[s[i + 1] ?? ""] ?? 0;
    total += v < next ? -v : v;
  }
  return total;
}

/** "30A" -> [30, "A"]; a part with no leading number sorts after every numbered one. */
function numberAndLetters(part: string): [number, string] {
  const m = /^(\d+)(.*)$/.exec(part);
  return m ? [Number(m[1]), m[2]!] : [Number.POSITIVE_INFINITY, part];
}

const compareParts = (a: string, b: string): number => {
  const [an, al] = numberAndLetters(a);
  const [bn, bl] = numberAndLetters(b);
  return an - bn || (al < bl ? -1 : al > bl ? 1 : 0);
};

/** Chapters in number order, a letter after the plain number ("30" < "30A" < "31"); ties end in the text itself. */
export function compareChapters(a: string, b: string): number {
  return compareParts(a, b) || (a < b ? -1 : a > b ? 1 : 0);
}

/**
 * Sections in the order of the Revisor's chapter pages (checked on chapter 456 in October 2026): first the plain
 * sections by the number after the dot read as a whole number (1.190 before 1.1001, 456.995 before 456.1000), then the
 * Uniform-Code style ones ("400.2A-101") by article (2 < 2A < 3 < 10), then section number, then a letter
 * ("456.4-411A" < "456.4-411B"). The chapter comes first, so ids from different chapters sort by chapter. Ties
 * end in the id itself, which is unique.
 */
export function compareSectionIds(a: string, b: string): number {
  const key = (id: string): [string, number, string, string] => {
    const dot = id.indexOf(".");
    const chapter = dot < 0 ? id : id.slice(0, dot);
    const rest = dot < 0 ? "" : id.slice(dot + 1);
    const dash = rest.indexOf("-");
    return dash < 0 ? [chapter, 0, "", rest] : [chapter, 1, rest.slice(0, dash), rest.slice(dash + 1)];
  };
  const [ac, ak, aa, as] = key(a);
  const [bc, bk, ba, bs] = key(b);
  return (
    compareChapters(ac, bc) ||
    ak - bk ||
    (ak === 1 ? compareParts(aa, ba) : 0) ||
    compareParts(as, bs) ||
    (a < b ? -1 : a > b ? 1 : 0)
  );
}

/** "12 of 30 sections in force": distinct section numbers, the way rpt_statute_chapters counts them. */
export function chapterCountsText(c: { sections: number; sections_in_force: number }): string {
  if (c.sections_in_force === 0) return `${plural(c.sections, "section", "sections")}, none in force`;
  if (c.sections_in_force === c.sections) {
    return c.sections === 1
      ? "1 section, in force"
      : `${plural(c.sections, "section", "sections")}, all in force`;
  }
  return `${count(c.sections_in_force)} of ${plural(c.sections, "section", "sections")} in force`;
}

/** The sections before and after `sectionId` in `ordered` (one chapter's ids in Revisor order), or null at an end. */
export function sectionNeighbors(
  ordered: readonly string[],
  sectionId: string,
): { prev: string | null; next: string | null } {
  const i = ordered.indexOf(sectionId);
  if (i < 0) return { prev: null, next: null };
  return { prev: ordered[i - 1] ?? null, next: ordered[i + 1] ?? null };
}

/**
 * The pages to build: one per section, or the single "not loaded yet" page without the exports. Lives here, not in
 * the page's frontmatter, because Astro hoists getStaticPaths to module scope where frontmatter constants do not exist.
 */
export function statutePaths(
  hasExports: boolean,
  refs: readonly { section_id: string }[],
): { params: { section: string } }[] {
  if (!hasExports) return [{ params: { section: NOT_LOADED } }];
  return refs.map((r) => ({ params: { section: r.section_id } }));
}

/** A repeal or transfer notice is not a text of the law, so it is not counted as a version. */
export const isNotice = (v: Pick<StatuteVersion, "status">): boolean =>
  v.status === "repealed" || v.status === "transferred";

/**
 * Per-version heading text and screen-reader context for the repeated "this version on revisor.mo.gov" link.
 * Versions whose labels collide (two current versions with one date) get "(version i of n)" so no two headings or
 * link names are alike.
 */
export function versionNames(versions: readonly StatusInput[]): { heading: string; context: string }[] {
  const labels = versions.map((v) => statusLabel(v).label);
  return versions.map((v, i) => {
    const same = labels.flatMap((l, j) => (l === labels[i] ? [j] : []));
    const heading =
      same.length > 1 ? `${labels[i]} (version ${same.indexOf(i) + 1} of ${same.length})` : labels[i]!;
    const when = v.effective_date ? `, ${longDate(v.effective_date)}` : "";
    return { heading, context: `(${heading}${when})` };
  });
}

/** The page's lead sentences: the word-for-word promise only where there is text, and a count of real versions. */
export function introText(versions: readonly Pick<StatuteVersion, "status">[]): string {
  const texts = versions.filter((v) => !isNotice(v)).length;
  if (texts === 0) {
    return "The Revisor lists this section only as repealed or transferred. We add nothing to what it publishes.";
  }
  return (
    "The text below is word for word what the Revisor of Statutes publishes. We add nothing to it and leave nothing out." +
    (texts > 1 ? ` The Revisor lists ${texts} versions of this section.` : "")
  );
}
