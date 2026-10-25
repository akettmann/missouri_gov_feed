import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ALL_OFFICES,
  filterForOffice,
  filterOfficials,
  matchesOffice,
  reconcileFilter,
} from "../src/lib/compareFilter.ts";

const people = [
  { slug: "rep", office: "state_house" },
  { slug: "sen", office: "state_senate" },
  { slug: "sen2", office: "state_senate" },
  { slug: "gov", office: "governor" },
];
const slugs = (f) => filterOfficials(people, f).map((p) => p.slug);

test("all offices lists everyone, in order", () => {
  assert.deepEqual(slugs(ALL_OFFICES), ["rep", "sen", "sen2", "gov"]);
});

test("following a state senator's group offers House and Senate members only", () => {
  assert.deepEqual(filterForOffice("state_senate"), { group: "legislature", office: "" });
  assert.deepEqual(slugs(filterForOffice("state_senate")), ["rep", "sen", "sen2"]);
});

test("a single office chip narrows to that office", () => {
  assert.deepEqual(slugs({ group: "legislature", office: "state_senate" }), ["sen", "sen2"]);
});

test("the office chip wins over the group", () => {
  assert.equal(matchesOffice("state_house", { group: "legislature", office: "state_senate" }), false);
});

test("no first pick means no narrowing", () => {
  assert.deepEqual(filterForOffice(undefined), ALL_OFFICES);
  assert.deepEqual(filterForOffice(""), ALL_OFFICES);
});

test("an unknown office falls in the other group, not dropped by All offices", () => {
  assert.equal(matchesOffice("brand_new_office", ALL_OFFICES), true);
  assert.equal(matchesOffice("brand_new_office", filterForOffice("brand_new_office")), true);
  assert.equal(matchesOffice("state_house", filterForOffice("brand_new_office")), false);
});

test("reconcile keeps a coherent filter", () => {
  const f = { group: "legislature", office: "state_senate" };
  assert.deepEqual(reconcileFilter(f), f);
  assert.deepEqual(reconcileFilter(ALL_OFFICES), ALL_OFFICES);
  assert.deepEqual(reconcileFilter({ group: "statewide", office: "" }), { group: "statewide", office: "" });
});

test("reconcile drops an office that is not in the group", () => {
  assert.deepEqual(reconcileFilter({ group: "statewide", office: "state_senate" }), {
    group: "statewide",
    office: "",
  });
  assert.deepEqual(slugs(reconcileFilter({ group: "statewide", office: "state_senate" })), ["gov"]);
});

test("reconcile gives an office without a group its own group", () => {
  assert.deepEqual(reconcileFilter({ group: "", office: "state_senate" }), {
    group: "legislature",
    office: "state_senate",
  });
  assert.deepEqual(slugs(reconcileFilter({ group: "", office: "state_senate" })), ["sen", "sen2"]);
});
