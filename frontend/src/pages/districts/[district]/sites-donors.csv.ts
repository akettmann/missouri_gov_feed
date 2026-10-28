// CSV download of the donors behind the matched sites of one district: one line per site, donor and filing page.
import type { APIRoute, GetStaticPaths } from "astro";
import { districtSiteLists, districtSites } from "../../../lib/exports/districtSites";
import { sitesDonorsCsv } from "../../../lib/siteCsv";

export const getStaticPaths = (async () => {
  const lists = await districtSiteLists();
  return [...(lists?.values() ?? [])].map((l) => ({
    params: { district: l.slug },
    props: { districtId: l.district_id },
  }));
}) satisfies GetStaticPaths;

export const GET: APIRoute<{ districtId: string }> = async ({ props }) =>
  new Response(sitesDonorsCsv(await districtSites(props.districtId)), {
    headers: { "Content-Type": "text/csv; charset=utf-8" },
  });
