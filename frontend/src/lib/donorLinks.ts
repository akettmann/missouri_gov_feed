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

export interface DonorEntry {
  donor: string;
  /** filing pages for this donor; empty when the donor has none (rendered as "no link") */
  urls: string[];
}

/**
 * One entry per donor, in donor_names order (names are joined by "; "), each with its filing-page urls from
 * donor_links. A donor named in donor_names with no link line has an empty list, so the page can say "no link"
 * instead of showing the name bare (#268). A link whose donor is not in donor_names is kept, after the others.
 * Donors whose pages are exactly the same collapse into one entry whose `donor` joins their names with "; ".
 * donor_names itself never holds a "; " inside a name: fct_jurisdiction_businesses turns each ";" into a comma (#276).
 */
export function donorEntries(
  names: string | null | undefined,
  rawLinks: string | null | undefined,
): DonorEntry[] {
  const links = parseDonorLinks(rawLinks);
  const order: string[] = [];
  for (const n of (names ?? "").split("; ")) {
    const name = n.trim();
    if (name && !order.includes(name)) order.push(name);
  }
  for (const l of links) if (!order.includes(l.donor)) order.push(l.donor);
  const entries: DonorEntry[] = [];
  const byPages = new Map<string, DonorEntry>();
  for (const donor of order) {
    const urls = [...new Set(links.filter((l) => l.donor === donor).map((l) => l.url))];
    // Name variants of one committee (one per spelling it filed under) all link the same pages: show those
    // pages once, under all the names, instead of the same link once per variant (#276). A donor with no
    // page is never merged, so "no link" stays attached to its own name.
    const key = urls.slice().sort().join(" ");
    const same = urls.length ? byPages.get(key) : undefined;
    if (same) {
      same.donor += `; ${donor}`;
      continue;
    }
    const entry = { donor, urls };
    entries.push(entry);
    if (urls.length) byPages.set(key, entry);
  }
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
