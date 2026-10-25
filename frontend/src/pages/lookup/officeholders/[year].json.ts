// One past year of the browse list, loaded by the year control on the officials page when a visitor picks it.
import type { APIRoute, GetStaticPaths } from "astro";
import { currentAwardsBySlug } from "../../../lib/exports/awards";
import { pastOfficeholders } from "../../../lib/exports/load";
import type { PastOfficeholder } from "../../../lib/exports/types";
import { LEVELS, officeGroup, officeLine } from "../../../lib/format";

export const getStaticPaths = (async () => {
  const past = await pastOfficeholders();
  return [...(past?.years ?? [])].map(([year, rows]) => ({
    params: { year: String(year) },
    props: { rows },
  }));
}) satisfies GetStaticPaths;

export const GET: APIRoute = async ({ props }) => {
  const awards = await currentAwardsBySlug();
  // [name, slug, office, office group, office line, district, party, level label, current award badges]:
  // the row the page draws (badges only for people who hold awards now)
  const rows = (props.rows as PastOfficeholder[]).map((o) => [
    o.full_name,
    o.slug,
    o.office,
    officeGroup(o.office),
    officeLine(o),
    o.district,
    o.party,
    LEVELS[o.level] ?? o.level,
    ...(awards.has(o.slug) ? [awards.get(o.slug)] : []),
  ]);
  return new Response(JSON.stringify(rows), { headers: { "Content-Type": "application/json" } });
};
