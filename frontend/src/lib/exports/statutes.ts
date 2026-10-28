// Build-time loader for the RSMo section pages (#840): fct_statute_sections + fct_statute_section_footnotes.
// ~44k sections and 52 M characters of text: the ids come from one small query, the text is read one chapter
// at a time (a few chapters stay cached because Astro renders pages concurrently), never as one object.
import { hasExport, query } from "./db";
import type { StatuteFootnote, StatuteVersion } from "../statuteText";

/** True when both statute exports are there; pages say "not loaded yet" otherwise. */
export const hasStatuteExports = (): boolean =>
  hasExport("fct_statute_sections") && hasExport("fct_statute_section_footnotes");

export interface StatuteSectionRef {
  section_id: string;
  chapter: string;
}

let refs: Promise<StatuteSectionRef[]> | undefined;

/**
 * Every distinct section id with its chapter, ordered by chapter then id. A section whose versions name
 * different chapters would be a data fault; the smallest chapter is used so the result stays deterministic.
 */
export function statuteSectionRefs(): Promise<StatuteSectionRef[]> {
  refs ??= query<StatuteSectionRef>(`
    select section_id, coalesce(min(chapter), '') as chapter
    from {fct_statute_sections}
    group by section_id
    order by coalesce(min(chapter), ''), section_id`);
  return refs;
}

let idSet: Promise<Map<string, string>> | undefined;

/** section_id -> chapter, for checking that a link target (a transfer's new section) has a page. */
export function statuteSectionChapters(): Promise<Map<string, string>> {
  idSet ??= statuteSectionRefs().then((r) => new Map(r.map((x) => [x.section_id, x.chapter])));
  return idSet;
}

type SectionRow = Omit<StatuteVersion, "footnotes">;
type FootnoteRow = StatuteFootnote & { section_version_id: string };

const CACHED_CHAPTERS = 4;
const chapters = new Map<string, Promise<Map<string, StatuteVersion[]>>>();

async function readChapter(chapter: string): Promise<Map<string, StatuteVersion[]>> {
  const sections = await query<SectionRow>(
    `select section_id, bid::int as bid, section_version_id, chapter, chapter_name, title_numeral, title_name,
            heading, status, is_current, effective_date::varchar as effective_date, held_unconstitutional,
            ended_date::varchar as ended_date, transferred_to, history_note, section_text, repeal_pending,
            source_url, loaded_at::varchar as loaded_at
     from {fct_statute_sections}
     where coalesce(chapter, '') = ?
     order by section_id, bid`,
    [chapter],
  );
  const notes = await query<FootnoteRow>(
    `select f.section_version_id, f.footnote_number::int as footnote_number, f.footnote_text, f.is_history_note
     from {fct_statute_section_footnotes} f
     join {fct_statute_sections} s on s.section_version_id = f.section_version_id
     where coalesce(s.chapter, '') = ?
     order by f.section_version_id, f.footnote_number`,
    [chapter],
  );
  const byVersion = new Map<string, StatuteFootnote[]>();
  for (const { section_version_id, ...n } of notes) {
    const list = byVersion.get(section_version_id) ?? [];
    list.push(n);
    byVersion.set(section_version_id, list);
  }
  const out = new Map<string, StatuteVersion[]>();
  for (const s of sections) {
    const list = out.get(s.section_id) ?? [];
    list.push({ ...s, footnotes: byVersion.get(s.section_version_id) ?? [] });
    out.set(s.section_id, list);
  }
  return out;
}

/** One chapter's versions grouped by section id (versions in bid order). Recently used chapters stay cached. */
export function statuteChapter(chapter: string): Promise<Map<string, StatuteVersion[]>> {
  let p = chapters.get(chapter);
  if (p) {
    chapters.delete(chapter); // re-insert: Map order = least recently used first
  } else {
    p = readChapter(chapter);
    p.catch(() => chapters.delete(chapter));
  }
  chapters.set(chapter, p);
  while (chapters.size > CACHED_CHAPTERS) chapters.delete(chapters.keys().next().value as string);
  return p;
}

/** The versions of one section, or [] when the id is unknown. */
export async function statuteVersions(sectionId: string): Promise<StatuteVersion[]> {
  const chapter = (await statuteSectionChapters()).get(sectionId);
  if (chapter === undefined) return [];
  return (await statuteChapter(chapter)).get(sectionId) ?? [];
}
