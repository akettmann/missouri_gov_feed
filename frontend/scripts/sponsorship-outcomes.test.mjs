import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  MIN_DECIDED_FOR_SHARE,
  buildSponsorshipSessions,
  countWithShare,
  sharePct,
  summaryLine,
} from "../src/lib/sponsorshipOutcomes.ts";

const row = (official_id, session_code, extra = {}) => ({
  official_id,
  session_code,
  session_year: 2000 + Number(session_code.slice(0, 2)),
  is_session_over: true,
  bills_sponsored: 10,
  bills_decided: 10,
  bills_passed_house: 4,
  bills_became_law: 2,
  source_url: `https://documents.house.mo.gov/xml/${session_code}.zip`,
  ...extra,
});
const NAMES = new Map([
  ["251", "2025 Regular Session"],
  ["241", "2024 Regular Session"],
]);

test("the share needs at least 5 decided bills; under it, counts only", () => {
  assert.equal(MIN_DECIDED_FOR_SHARE, 5);
  assert.equal(sharePct(2, 4), null);
  assert.equal(sharePct(0, 0), null);
  assert.equal(sharePct(2, 5), 40);
  assert.equal(sharePct(3, 8), 38);
  assert.equal(sharePct(0, 7), 0);
  const [s] = buildSponsorshipSessions([row("a", "251", { bills_decided: 4, bills_sponsored: 4 })]).get("a");
  assert.equal(s.passed_house_pct, null);
  assert.equal(s.became_law_pct, null);
  assert.equal(countWithShare(3, 4, s.passed_house_pct), "3 of 4");
  assert.equal(countWithShare(3, 8, 38), "3 of 8 (38%)");
});

test("a member with zero passed bills still shows a share of 0% once n is large enough", () => {
  const [s] = buildSponsorshipSessions([
    row("plank", "251", { bills_passed_house: 0, bills_became_law: 0 }),
  ]).get("plank");
  assert.equal(s.passed_house_pct, 0);
  assert.equal(countWithShare(s.bills_passed_house, s.bills_decided, s.passed_house_pct), "0 of 10 (0%)");
});

test("a session still open is labelled in progress, and a finished one is not", () => {
  const rows = [
    row("a", "251", { is_session_over: false, bills_sponsored: 12, bills_decided: 2 }),
    row("a", "241"),
  ];
  const [open, done] = buildSponsorshipSessions(rows, NAMES).get("a");
  assert.equal(open.in_progress, true);
  assert.match(open.summary, /session in progress/);
  assert.equal(done.in_progress, false);
  assert.doesNotMatch(done.summary, /in progress/);
  assert.equal(open.label, "2025 Regular Session");
});

test("summary wording names what each number counts", () => {
  assert.equal(
    summaryLine(row("a", "241")),
    "Sponsored 10 bills, 10 decided; 4 passed the House; 2 became law",
  );
  assert.equal(
    summaryLine(
      row("a", "241", { bills_sponsored: 1, bills_decided: 0, bills_passed_house: 0, bills_became_law: 0 }),
    ),
    "Sponsored 1 bill; none decided yet",
  );
});

test("sessions are grouped per official, newest first, and an unnamed session says so", () => {
  const out = buildSponsorshipSessions([row("a", "241"), row("b", "261"), row("a", "251")], NAMES);
  assert.deepEqual(
    out.get("a").map((s) => s.session_code),
    ["251", "241"],
  );
  assert.equal(out.get("b")[0].label, "session code 261");
  assert.equal(out.get("c"), undefined);
});

test("the section says Not available yet for a missing export, and carries the caveats and the source link", () => {
  const src = readFileSync(new URL("../src/components/SectionSponsorship.astro", import.meta.url), "utf8");
  assert.match(
    src,
    /sessions === null \? \(\s*<p class="muted small">Not available yet \(the fct_sponsorship_outcomes export is missing\)/,
  );
  assert.match(src, /Current\s+officials\s+only/);
  assert.match(src, /not\s+comparable\s+with\s+recent\s+sessions/);
  assert.match(src, /<SourceLink url=\{s\.source_url\}/);
  const load = readFileSync(new URL("../src/lib/exports/load.ts", import.meta.url), "utf8");
  assert.match(load, /hasExport\("fct_sponsorship_outcomes"\)\s*\? buildSponsorshipSessions/);
});
