// What a donor "reports" link on the sites and businesses tables really opens. fct_jurisdiction_businesses
// builds contributions_url from the campaign-finance rows it summed: an MEC row links the committee that
// RECEIVED the money (the one matched to the official), not filtered to the donor; an FEC row links the donor
// committee's disbursements filtered to the receiving committee. The label names the page instead of promising
// "reports" for the donor (#236).
// Pure and import-free so node:test can load it.

/** visible link text for a contributions_url, by which regulator's page it is */
export function donorLinkLabel(url: string | null | undefined): string {
  if (!url) return "committee page";
  if (url.includes("mec.mo.gov")) return "official's committee (MEC)";
  if (url.includes("fec.gov")) return "donor's gifts to this committee (FEC)";
  return "committee page";
}
