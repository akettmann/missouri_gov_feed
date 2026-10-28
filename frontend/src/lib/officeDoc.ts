// Parses docs/reference/office_responsibilities.md (and its sibling office_requirements.md, same layout) with a
// real markdown lexer, so the legal text has one source of truth: the doc. The parser is strict on purpose.
// A bullet with no citation link, a footnote out of order, an unresolved link reference or an unknown source
// name throws, so the build (and the tests) fail when the doc's structure drifts.
import { Lexer, Parser, type Token, type Tokens } from "marked";

export interface DocLink {
  text: string;
  href: string;
}

export interface DocBullet {
  /** Bold lead-in: "Duty", "Power", "Job", "Limit", or "Duty (Supreme Court)". */
  label: string;
  /** The bullet's text as HTML, citation links included, without the lead-in or the Data clause. */
  html: string;
  citations: DocLink[];
  /** The "Data:" clause as HTML; null for docs without one (requirements). */
  dataHtml: string | null;
  /** Loaded project sources named in the Data clause (loader names), in order of first use. */
  sources: string[];
  /** Researched sources named in the Data clause that are not loaded yet. */
  candidates: string[];
  /** True when the Data clause names no loaded source. */
  noData: boolean;
}

export interface DocNote {
  n: number;
  html: string;
  citations: DocLink[];
}

export interface DocSection {
  title: string;
  id: string;
  /** Intro paragraphs of the section, as HTML. */
  introHtml: string;
  bullets: DocBullet[];
  notes: DocNote[];
}

export interface OfficeDoc {
  title: string;
  /** ISO date from the "Legal text checked YYYY-MM-DD" line. */
  checked: string;
  /** Everything between the title and the first section (how to read, words used), as HTML. */
  prefaceHtml: string;
  /** Sections with bullets: one per office. */
  offices: DocSection[];
  /** Sections without bullets (for example "Offices not covered yet"). */
  otherSections: DocSection[];
  /** Reader-facing names by code name (empty when the caller gave none). */
  names: ReadonlyMap<string, string>;
}

export interface ParseOptions {
  /** Every bullet must carry a "Data:" clause naming sources (responsibilities); false for requirements. */
  requireData: boolean;
  /** Loader names that count as loaded sources (src/mogov/loaders/*.py). */
  loaders: ReadonlySet<string>;
  /** Code names allowed in a Data clause that are models, not sources. */
  models?: ReadonlySet<string>;
  /** Reader-facing names for loaders, candidates and models; a code name found here is shown by its name. */
  names?: ReadonlyMap<string, string>;
}

const fail = (where: string, why: string): never => {
  throw new Error(`office doc: ${where}: ${why}`);
};

export const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");

type LinkMap = Record<string, { href: string; title: string }>;

const render = (tokens: Token[], links: LinkMap | undefined) =>
  Parser.parse(Object.assign([...tokens], { links: links ?? {} }) as never).trim();
const renderInline = (tokens: Token[]) => Parser.parseInline(tokens).trim();

/** Child tokens of a block: a list keeps them in `items` (each with its own `tokens`), everything else in `tokens`. */
const hasKids = (t: Token) =>
  ("tokens" in t && Array.isArray(t.tokens)) || ("items" in t && Array.isArray(t.items));

/** Rebuilds a token with `f` applied to each child token list. */
function mapKids(t: Token, f: (kids: Token[]) => Token[]): Token {
  const o = t as unknown as { tokens?: Token[]; items?: Token[] };
  return {
    ...t,
    ...(Array.isArray(o.tokens) ? { tokens: f(o.tokens) } : {}),
    ...(Array.isArray(o.items) ? { items: f(o.items) } : {}),
  } as Token;
}

const kidsOf = (t: Token): Token[] => {
  const o = t as unknown as { tokens?: Token[]; items?: Token[] };
  return [...(o.tokens ?? []), ...(o.items ?? [])];
};

/** Every link token, however deeply nested in emphasis. */
function collectLinks(tokens: Token[], where: string): DocLink[] {
  const out: DocLink[] = [];
  for (const t of tokens) {
    if (t.type === "link") {
      const l = t as Tokens.Link;
      if (!/^https:\/\//.test(l.href)) fail(where, `link "${l.text}" is not an https URL (${l.href})`);
      out.push({ text: l.text, href: l.href });
    } else if (hasKids(t)) out.push(...collectLinks(kidsOf(t), where));
  }
  return out;
}

/**
 * A "[x][y]" or a bare "[x]" the lexer could not resolve stays as literal text: a citation lost to a typo.
 * docs/reference/office_responsibilities.md has no literal square brackets in its text (write a footnote
 * marker as `\[5\]` if one is ever needed), so any "[...]" left in a text token is a bug.
 */
function assertResolved(tokens: Token[], where: string) {
  for (const t of tokens) {
    if (t.type === "text" && /\[[^\]]*\]/.test((t as Tokens.Text).raw))
      fail(where, `unresolved link reference in "${(t as Tokens.Text).raw.trim()}"`);
    if (hasKids(t)) assertResolved(kidsOf(t), where);
  }
}

const isInlineComment = (t: Token) => t.type === "html" && /^\s*<!--[\s\S]*-->\s*$/.test(t.raw);

/** Drops inline HTML comments (maintainer notes in the middle of a paragraph), however deeply nested. */
function stripInlineComments(tokens: Token[]): Token[] {
  return tokens.filter((t) => !isInlineComment(t)).map((t) => mapKids(t, stripInlineComments));
}

/** Shows a code name that has a reader-facing name by that name; other code stays as code. */
function plainNames(tokens: Token[], names: ReadonlyMap<string, string> | undefined): Token[] {
  if (!names) return tokens;
  return tokens.map((t) => {
    if (t.type === "codespan" && names.has((t as Tokens.Codespan).text))
      return textToken(names.get((t as Tokens.Codespan).text)!);
    return mapKids(t, (kids) => plainNames(kids, names));
  }) as Token[];
}

function itemInline(item: Tokens.ListItem, where: string): Token[] {
  const first = item.tokens[0] as Tokens.Text | undefined;
  if (!first || (first.type !== "text" && first.type !== "paragraph") || !first.tokens)
    return fail(where, "list item has no inline text");
  if (item.tokens.length > 1) fail(where, "list item has nested blocks; use one paragraph per bullet");
  return stripInlineComments(first.tokens);
}

function textToken(s: string): Tokens.Text {
  return { type: "text", raw: s, text: s };
}

function parseBullet(item: Tokens.ListItem, where: string, opt: ParseOptions): DocBullet {
  const inline = itemInline(item, where);
  assertResolved(inline, where);
  const [lead, ...rest] = inline;
  if (lead?.type !== "strong") return fail(where, "bullet must start with a bold label such as **Duty.**");
  const label = (lead as Tokens.Strong).text.replace(/\.$/, "").trim();
  if (!/^[A-Z][A-Za-z ]*( \([^)]+\))?$/.test(label)) fail(where, `odd label "${label}"`);

  // Split at the first "Data:" inside a text token.
  const split = rest.findIndex((t) => t.type === "text" && (t as Tokens.Text).raw.includes("Data:"));
  let body: Token[] = rest;
  let data: Token[] | null = null;
  if (split !== -1) {
    const raw = (rest[split] as Tokens.Text).raw;
    const cut = raw.indexOf("Data:");
    body = [...rest.slice(0, split), textToken(raw.slice(0, cut))];
    data = [textToken(raw.slice(cut + "Data:".length)), ...rest.slice(split + 1)];
  }
  if (opt.requireData && !data) fail(where, 'bullet has no "Data:" clause');
  if (!opt.requireData && data) fail(where, 'unexpected "Data:" clause');

  const citations = collectLinks(body, where);
  if (citations.length === 0) fail(where, "bullet has no citation link");

  const sources: string[] = [];
  const candidates: string[] = [];
  (data ?? []).forEach((t, i, all) => {
    if (t.type !== "codespan") return;
    const name = (t as Tokens.Codespan).text;
    if (name.includes("/")) return; // a file path, not a source name
    const next = all[i + 1];
    const isCandidate = next?.type === "text" && /^\s+is not loaded yet/.test((next as Tokens.Text).raw);
    if (isCandidate) {
      if (!candidates.includes(name)) candidates.push(name);
    } else if (opt.loaders.has(name)) {
      if (!sources.includes(name)) sources.push(name);
    } else if (!opt.models?.has(name)) {
      fail(where, `"${name}" in Data is not a loader, a known model or marked "is not loaded yet"`);
    }
  });
  if (
    data &&
    sources.length === 0 &&
    !/\bno (?:[\w-]+ )?data yet/i.test(
      data
        .map((t) => t.raw)
        .join("")
        .replace(/\s+/g, " "),
    )
  )
    fail(where, 'Data clause names no loaded source and does not say "no data yet"');

  return {
    label,
    html: renderInline(plainNames(body, opt.names)),
    citations,
    dataHtml: data ? renderInline(plainNames(data, opt.names)).replace(/\.$/, "") : null,
    sources,
    candidates,
    noData: opt.requireData && sources.length === 0,
  };
}

function parseNote(item: Tokens.ListItem, n: number, where: string, opt: ParseOptions): DocNote {
  const inline = itemInline(item, where);
  const first = inline[0] as Tokens.Text | undefined;
  const m = first?.type === "text" ? /^\[(\d+)\]\s*/.exec(first.raw) : null;
  if (!m) return fail(where, 'note must start with "[n]"');
  if (Number(m[1]) !== n) fail(where, `note numbered [${m[1]}], expected [${n}]`);
  const body: Token[] = [textToken(first!.raw.slice(m[0].length)), ...inline.slice(1)];
  assertResolved(body, where);
  const citations = collectLinks(body, where);
  if (citations.length === 0) fail(where, "note has no citation link");
  return { n, html: renderInline(plainNames(body, opt.names)), citations };
}

const isNotesMarker = (t: Token) =>
  t.type === "paragraph" && (t as Tokens.Paragraph).text.trim() === "Notes:";

export function parseOfficeDoc(markdown: string, opt: ParseOptions): OfficeDoc {
  const tokens = new Lexer().lex(markdown);
  const links = (tokens as unknown as { links?: LinkMap }).links;
  // Block-level HTML comments are maintainer notes (issue numbers, reading level): never rendered.
  const isComment = (t: Token) => t.type === "html" && /^\s*<!--[\s\S]*-->\s*$/.test(t.raw);
  const blocks = tokens
    .filter((t) => t.type !== "space" && !isComment(t))
    .map((t) => mapKids(t, stripInlineComments));

  const h1 = blocks[0];
  if (h1?.type !== "heading" || (h1 as Tokens.Heading).depth !== 1)
    fail("top", "doc must start with a # title");
  const title = (h1 as Tokens.Heading).text;

  const firstH2 = blocks.findIndex((t) => t.type === "heading" && (t as Tokens.Heading).depth === 2);
  if (firstH2 === -1) fail("top", "doc has no ## sections");
  const preface = blocks.slice(1, firstH2);
  assertResolved(preface, "top");
  const dateMatch = /Legal text checked (\d{4}-\d{2}-\d{2})/.exec(preface.map((t) => t.raw).join(""));
  if (!dateMatch) fail("top", 'preface lacks "Legal text checked YYYY-MM-DD"');

  const offices: DocSection[] = [];
  const otherSections: DocSection[] = [];
  const ids = new Set<string>();
  for (let i = firstH2; i < blocks.length;) {
    const h = blocks[i] as Tokens.Heading;
    if (h.type !== "heading" || h.depth !== 2) fail("section", `unexpected ${h.type} outside a ## section`);
    let j = i + 1;
    while (j < blocks.length && !(blocks[j].type === "heading" && (blocks[j] as Tokens.Heading).depth <= 2))
      j++;
    const body = blocks.slice(i + 1, j);
    i = j;

    const id = slug(h.text);
    if (ids.has(id)) fail(h.text, "duplicate section id");
    ids.add(id);
    const where = h.text;
    const lists = body.filter((t) => t.type === "list") as Tokens.List[];
    if (lists.length > 2) fail(where, "more than two lists (expected bullets, then notes)");
    const hasMarker = body.some(isNotesMarker);
    if (lists.length === 2 && !hasMarker) fail(where, 'second list must follow a "Notes:" line');
    if (lists.length < 2 && hasMarker) fail(where, '"Notes:" without a notes list');
    const intro = body.filter((t) => t.type !== "list" && !isNotesMarker(t));
    assertResolved(intro, where);

    const bullets = lists[0]
      ? lists[0].items.map((it, k) => parseBullet(it, `${where} bullet ${k + 1}`, opt))
      : [];
    const notes = lists[1]
      ? lists[1].items.map((it, k) => parseNote(it, k + 1, `${where} note ${k + 1}`, opt))
      : [];
    const section: DocSection = {
      title: h.text,
      id,
      introHtml: render(plainNames(intro, opt.names), links),
      bullets,
      notes,
    };
    // A section with no bullets and no text (the trailing "## Links" of reference definitions) shows nothing.
    if (bullets.length === 0 && section.introHtml === "") continue;
    (bullets.length > 0 ? offices : otherSections).push(section);
  }
  if (offices.length === 0) fail("top", "no section has bullets");

  return {
    title,
    checked: dateMatch![1],
    prefaceHtml: render(plainNames(preface, opt.names), links),
    offices,
    otherSections,
    names: opt.names ?? new Map(),
  };
}

export interface OfficeCoverageCell {
  source: string;
  /** Reader-facing name; the code name when none is known. */
  name: string;
  kind: "loaded" | "candidate";
  /** How many of the office's bullets name this source. */
  bullets: number;
}

/** One strip cell per source an office's bullets name, plus how many bullets have no loaded source. */
export function officeCoverage(section: DocSection, names: ReadonlyMap<string, string> = new Map()) {
  const cells = new Map<string, OfficeCoverageCell>();
  const bump = (source: string, kind: OfficeCoverageCell["kind"]) => {
    const key = `${kind}:${source}`;
    const c = cells.get(key) ?? { source, name: names.get(source) ?? source, bullets: 0, kind };
    c.bullets++;
    cells.set(key, c);
  };
  for (const b of section.bullets) {
    b.sources.forEach((s) => bump(s, "loaded"));
    b.candidates.forEach((s) => bump(s, "candidate"));
  }
  // Loaded before candidates, then by name, then code name; (kind, source) is unique, so the order is total.
  const sorted = [...cells.values()].sort(
    (a, b) =>
      Number(a.kind === "candidate") - Number(b.kind === "candidate") ||
      a.name.localeCompare(b.name) ||
      a.source.localeCompare(b.source),
  );
  return {
    cells: sorted,
    total: section.bullets.length,
    noData: section.bullets.filter((b) => b.noData).length,
  };
}
