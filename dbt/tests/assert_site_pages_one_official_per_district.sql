-- The district EPA site pages (frontend/src/lib/exports/districtSites.ts) key a page by district but write it for
-- one official, so each district maps to one official and each official to one district, and a facility is listed
-- once per district. A roster change that breaks that (a vacated seat plus its successor, a special election, an
-- official with two relations) fails here instead of in the frontend build. #134
{{ site_page_violations(ref('fct_jurisdiction_businesses')) }}
