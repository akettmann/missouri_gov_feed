// Pure helpers for serving the site under a subpath (GitHub Pages project sites: /missouri_gov_feed/).
// Astro exposes the configured base as import.meta.env.BASE_URL ("/" when unset, else "/sub/" or "/sub").

/** "/" and "" -> ""; "/sub/" -> "/sub". Always safe to prefix onto an absolute path. */
export function stripTrailingSlash(baseUrl: string): string {
  return baseUrl.replace(/\/+$/, "");
}

/** Prefix an absolute site path ("/officials/x/") with the base. */
export function withBase(baseUrl: string, path: string): string {
  return `${stripTrailingSlash(baseUrl)}${path}`;
}
