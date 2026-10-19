// The per-official JSON: what the profile's charts load, and the "download this data" file.
import type { APIRoute, GetStaticPaths } from "astro";
import { allOfficials } from "../../lib/exports/load";
import type { OfficialBundle } from "../../lib/exports/types";

export const getStaticPaths = (async () =>
  (await allOfficials()).map((bundle) => ({
    params: { slug: bundle.official.slug },
    props: { bundle },
  }))) satisfies GetStaticPaths;

export const GET: APIRoute<{ bundle: OfficialBundle }> = ({ props }) =>
  new Response(JSON.stringify(props.bundle), { headers: { "Content-Type": "application/json" } });
