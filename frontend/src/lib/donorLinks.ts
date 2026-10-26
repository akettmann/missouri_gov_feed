// What a donor "reports" link on the sites and businesses tables really opens. fct_jurisdiction_businesses
// builds donor_links from the campaign-finance rows it summed, one `<url> <donor name>` line per donor and
// filing page: an MEC row links the committee that RECEIVED the money (the one matched to the official), not
// filtered to the donor; an FEC row links the donor committee's disbursements filtered to the receiving
// committee. The label names the page instead of promising "reports" for the donor (#236), and each donor
// gets its own link instead of the row sharing one (#248).
// Pure and import-free so node:test can load it.

export interface DonorLink {
  url: string;
  /** the donor the link is for, as filed */
  donor: string;
}

/**
 * Split fct_jurisdiction_businesses.donor_links into links. A url never contains a space, so each line splits
 * at its first one; a line with no url or no donor name is dropped rather than rendered as a blank link.
 */
export function parseDonorLinks(raw: string | null | undefined): DonorLink[] {
  if (!raw) return [];
  const links: DonorLink[] = [];
  for (const line of raw.split("\n")) {
    const i = line.indexOf(" ");
    if (i <= 0) continue;
    const donor = line.slice(i + 1).trim();
    if (donor) links.push({ url: line.slice(0, i), donor });
  }
  return links;
}

/** the committee ids a filing-page url names: MEC's MECID, or FEC's committee_id and recipient_name */
function committeeIds(url: string): string[] {
  try {
    const q = new URL(url).searchParams;
    return (url.includes("mec.mo.gov") ? ["MECID"] : ["committee_id", "recipient_name"]).map(
      (k) => q.get(k) ?? "",
    );
  } catch {
    return [];
  }
}

/**
 * visible link text for a filing-page url, by which regulator's page it is. When the donor has 2+ pages of the
 * same kind (`siblings`, all the donor's urls), the committee id that tells them apart goes in the label, so the
 * links do not share one name though they open different pages. A donor's single page is left unchanged.
 */
export function donorLinkLabel(url: string | null | undefined, siblings: string[] = []): string {
  if (!url) return "committee page";
  const kind = url.includes("mec.mo.gov") ? "MEC" : url.includes("fec.gov") ? "FEC" : null;
  if (!kind) return "committee page";
  const base = kind === "MEC" ? "official's committee" : "donor's gifts to the official's committee";
  const same = siblings.filter((u) => (kind === "MEC" ? u.includes("mec.mo.gov") : u.includes("fec.gov")));
  if (same.length < 2) return `${base} (${kind})`;
  const mine = committeeIds(url);
  const all = same.map(committeeIds);
  const varying = mine.filter((id, i) => id && all.some((o) => o[i] !== id));
  return varying.length ? `${base} (${kind}, ${varying.join(", ")})` : `${base} (${kind})`;
}

/**
 * fct_jurisdiction_businesses joins `donor_name_list` with this ASCII unit separator, not "; ": donor names are
 * kept as filed and a filed name can hold ";" or "," (e.g. "Missouri and Kansas Laborers; PAC"), so no printable
 * separator is safe (#350). The loader splits it once with `splitDonorNames`; everything downstream (pages, CSV,
 * JSON downloads) takes a `string[]` and the separator never leaves the loader. Show with `donorNamesText`.
 */
export const DONOR_NAME_SEPARATOR = "\u001f";

/** The donors in a `donor_name_list` value, trimmed, blanks dropped; null or empty gives []. */
export function splitDonorNames(names: string | null | undefined): string[] {
  return (names ?? "")
    .split(DONOR_NAME_SEPARATOR)
    .map((n) => n.trim())
    .filter(Boolean);
}

/** The donors for people to read: joined by "; ". */
export function donorNamesText(donors: readonly string[] | null | undefined): string {
  return (donors ?? []).join("; ");
}

export interface DonorEntry {
  donor: string;
  /** filing pages for this donor; empty when the donor has none (rendered as "no link") */
  urls: string[];
}

/**
 * One entry per donor, in the order given, each with its filing-page urls from
 * donor_links. A donor in the list with no link line has an empty list, so the page can say "no link"
 * instead of showing the name bare (#268). A link whose donor is not in the list is kept, after the others.
 * Donors whose gifts are filed on the same pages collapse into one entry whose `donor` joins their names with
 * "; ": exactly equal page sets, or a donor whose pages are all among another donor's (never partial overlap).
 * Sharing a page is not proof of one organisation: an MEC page is the official's own committee, so it is shared
 * by every donor to that official. The merge only avoids repeating a link; the page still names no more than it did.
 */
export function donorEntries(
  donors: readonly string[] | null | undefined,
  rawLinks: string | null | undefined,
): DonorEntry[] {
  const links = parseDonorLinks(rawLinks);
  const order: string[] = [];
  for (const name of donors ?? []) {
    if (!order.includes(name)) order.push(name);
  }
  for (const l of links) if (!order.includes(l.donor)) order.push(l.donor);
  // Group donors whose pages are exactly the same: donors whose gifts are filed on the same pages (for MEC,
  // the official's own committee), so show those pages once under all the names (#276). Sharing pages is not
  // proof of one organisation. A donor with no page is never merged, so "no link" stays attached to its own name.
  interface Group {
    names: { name: string; at: number }[];
    urls: string[];
  }
  const groups: Group[] = [];
  const byPages = new Map<string, Group>();
  order.forEach((donor, at) => {
    const urls = [...new Set(links.filter((l) => l.donor === donor).map((l) => l.url))];
    const key = urls.slice().sort().join(" ");
    const same = urls.length ? byPages.get(key) : undefined;
    if (same) {
      same.names.push({ name: donor, at });
      return;
    }
    const group = { names: [{ name: donor, at }], urls };
    groups.push(group);
    if (urls.length) byPages.set(key, group);
  });
  // Then fold a group whose pages are a strict subset of another group's into it, so no filing page is
  // repeated on a row (#342). Subset only, never partial overlap: two donors that each have a page the other
  // lacks stay apart, and so do chains (A shares a page with B, B shares another with C: A and C are not
  // joined). A group folds only when exactly one maximal group contains it; if two incomparable groups both
  // do, which donor it belongs to is a guess, so it stays alone. Also never fold when the target's extra pages
  // (ones the folded donor lacks) include an FEC link: those are donor-specific ("donor's gifts to the official's
  // committee"), so the folded name would wrongly carry another donor's FEC link.
  const contains = (big: Group, small: Group) =>
    big.urls.length > small.urls.length && small.urls.every((u) => big.urls.includes(u));
  const maximal = groups.filter((g) => g.urls.length && !groups.some((o) => contains(o, g)));
  const folded = new Set<Group>();
  for (const g of groups) {
    if (!g.urls.length || maximal.includes(g)) continue;
    const homes = maximal.filter((m) => contains(m, g));
    if (homes.length !== 1) continue;
    if (homes[0].urls.some((u) => !g.urls.includes(u) && u.includes("fec.gov"))) continue;
    homes[0].names.push(...g.names);
    folded.add(g);
  }
  const entries: DonorEntry[] = groups
    .filter((g) => !folded.has(g))
    .map((g) => ({
      donor: g.names
        .sort((x, y) => x.at - y.at)
        .map((n) => n.name)
        .join("; "),
      urls: g.urls,
    }));
  return entries;
}

/**
 * DOM ids for one donor link: the donor-name span and the link-label span. The link is named by both
 * (aria-labelledby="<nameId> <labelId>") so each reads "<donor> <label>" to a screen reader instead of every link
 * on a multi-donor row sharing the same name (#268). `prefix` must be unique per row on the page.
 */
export function donorLinkIds(
  prefix: string,
  donorIndex: number,
  urlIndex: number,
): { nameId: string; labelId: string } {
  return { nameId: `${prefix}-d${donorIndex}-name`, labelId: `${prefix}-d${donorIndex}-l${urlIndex}` };
}
