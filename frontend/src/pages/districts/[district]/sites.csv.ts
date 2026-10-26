// CSV download of every EPA-regulated site in one district (the same rows as the sites page).
import type { APIRoute, GetStaticPaths } from "astro";
import { districtSiteLists, districtSites } from "../../../lib/exports/districtSites";
import { sitesCsv } from "../../../lib/siteCsv";

export const getStaticPaths = (async () => {
  const lists = await districtSiteLists();
  return [...(lists?.values() ?? [])].map((l) => ({
    params: { district: l.slug },
    props: { districtId: l.district_id },
  }));
}) satisfies GetStaticPaths;

export const GET: APIRoute<{ districtId: string }> = async ({ props }) =>
  new Response(sitesCsv(await districtSites(props.districtId)), {
    headers: { "Content-Type": "text/csv; charset=utf-8" },
  });
