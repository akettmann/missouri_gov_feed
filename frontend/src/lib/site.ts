import { stripTrailingSlash, withBase } from "./basePath";
// PUBLIC_REPORT_ERROR_URL overrides where "Report an error" goes (default: a prefilled GitHub issue).
const REPORT_BASE =
  import.meta.env.PUBLIC_REPORT_ERROR_URL ?? "https://github.com/akettmann/missouri_gov_feed/issues/new";

export function reportErrorUrl(subject: string, pageUrl: string): string {
  const params = new URLSearchParams({
    title: `Data error: ${subject}`,
    body: `Page: ${pageUrl}\n\nWhat looks wrong:\n\nWhere the correct information can be found (link):\n`,
    labels: "data-error",
  });
  return `${REPORT_BASE}?${params}`;
}

export const base = stripTrailingSlash(import.meta.env.BASE_URL);
export const href = (p: string) => withBase(import.meta.env.BASE_URL, p);
