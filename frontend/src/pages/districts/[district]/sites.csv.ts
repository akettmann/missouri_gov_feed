// CSV download of every EPA-regulated site in one district (the same rows as the sites page).
import type { APIRoute, GetStaticPaths } from "astro";
import { districtSiteLists, districtSites } from "../../../lib/exports/districtSites";

export const getStaticPaths = (async () => {
  const lists = await districtSiteLists();
  return [...(lists?.values() ?? [])].map((l) => ({
    params: { district: l.slug },
    props: { districtId: l.district_id },
  }));
}) satisfies GetStaticPaths;

const cell = (v: string | boolean | null) => {
  const s = v === null ? "" : String(v);
  return /[",\r\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
};

export const GET: APIRoute<{ districtId: string }> = async ({ props }) => {
  const rows = await districtSites(props.districtId);
  const head = [
    "facility_name",
    "address",
    "city",
    "postal_code",
    "industry",
    "owner_name",
    "parent_company_name",
    "gave_to_official",
    "epa_record_url",
  ];
  const lines = rows.map((r) =>
    [
      r.facility_name,
      r.address,
      r.city,
      r.postal_code,
      r.naics_description,
      r.owner_name,
      r.parent_company_name,
      r.is_donor,
      r.frs_url,
    ]
      .map(cell)
      .join(","),
  );
  return new Response([head.join(","), ...lines].join("\n") + "\n", {
    headers: { "Content-Type": "text/csv; charset=utf-8" },
  });
};
