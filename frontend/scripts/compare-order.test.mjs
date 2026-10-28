import assert from "node:assert/strict";
import { test } from "node:test";
import { compareRows } from "../src/lib/compare.ts";

// Pins the compare page section order to the profile order (#801): money in, gifts, interests, businesses,
// then voting, ideology, coverage. Fixed fixture, no exports needed.
const bundle = {
  official: { office: "state_house", office_title: "Representative", party: "R" },
  coverage: [{ key: "commercial_ties", label: "Commercial ties", status: "available" }],
  indicators: [{ indicator: "party_unity_pct", value: 90, period: 2024, detail: "state_house:1" }],
  peers: [],
  voting: { status: "available", party_breaks: [], attendance: [], attendance_pay: [], by_subject: [] },
  money: { status: "available", federal: [], cycles: { rows: [], sample: false } },
  gifts: { rows: [], sample: false },
  businesses: { donors: [], industries: [] },
  interests: { commercial_ties_status: "available", commercial_ties: [], family_ties: [] },
};

test("compare rows are grouped money-first, matching the profile", () => {
  const sections = [];
  for (const r of compareRows([bundle, bundle], false))
    if (sections.at(-1) !== r.section) sections.push(r.section);
  assert.deepEqual(sections, [
    "Office",
    "Money in",
    "Lobbyist gifts",
    "Personal interests",
    "Businesses in their area",
    "Voting",
    "Ideology",
    "Coverage",
  ]);
});
