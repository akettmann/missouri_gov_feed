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

/** visible link text for a filing-page url, by which regulator's page it is */
export function donorLinkLabel(url: string | null | undefined): string {
  if (!url) return "committee page";
  if (url.includes("mec.mo.gov")) return "official's committee (MEC)";
  if (url.includes("fec.gov")) return "donor's gifts to the official's committee (FEC)";
  return "committee page";
}
