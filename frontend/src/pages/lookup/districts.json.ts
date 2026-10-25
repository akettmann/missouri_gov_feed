// Everything the "find my officials" lookup needs, in one file the browser loads on first use.
import type { APIRoute } from "astro";
import { currentAwardsBySlug } from "../../lib/exports/awards";
import { districtData } from "../../lib/exports/districts";
import { allOfficials } from "../../lib/exports/load";
import { officeLine } from "../../lib/format";

export const GET: APIRoute = async () => {
  const data = await districtData();
  if (!data) return new Response("null", { headers: { "Content-Type": "application/json" } });
  // slug -> [name, office line, party, office, current award badges]: enough to list results without
  // loading every profile (the badges entry is left off for officials with none)
  const awards = await currentAwardsBySlug();
  const directory = Object.fromEntries(
    (await allOfficials()).map(({ official: o }) => [
      o.slug,
      awards.has(o.slug)
        ? [o.full_name, officeLine(o), o.party, o.office, awards.get(o.slug)]
        : [o.full_name, officeLine(o), o.party, o.office],
    ]),
  );
  const { map: _map, ...lookup } = data;
  return new Response(JSON.stringify({ ...lookup, directory }), {
    headers: { "Content-Type": "application/json" },
  });
};
