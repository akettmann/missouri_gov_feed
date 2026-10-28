import assert from "node:assert/strict";
import { test } from "node:test";
import { sumByTrailStatus } from "../src/lib/trailSummary.ts";

const d = (trail_status, total_amount) => ({ trail_status, total_amount });

test("sums dollars by status, each donor row once, in a fixed order", () => {
  const trails = [
    { donors: [d("individuals", 100), d("end of trail", 250), d("mec committee", 40)] },
    { donors: [d("end of trail", 750), d("not an mec filer", 5), d("ambiguous mec name", 1)] },
  ];
  assert.deepEqual(sumByTrailStatus(trails), [
    { kind: "end of trail", amount: 1000, rows: 2 },
    { kind: "not an mec filer", amount: 5, rows: 1 },
    { kind: "ambiguous mec name", amount: 1, rows: 1 },
    { kind: "individuals", amount: 100, rows: 1 },
    { kind: "mec committee", amount: 40, rows: 1 },
  ]);
});

test("cents are exact: 0.1 + 0.2 style float drift does not show", () => {
  const trails = [
    { donors: [d("end of trail", 0.29), d("end of trail", 1.15), d("end of trail", 1234567.89)] },
  ];
  assert.equal(sumByTrailStatus(trails)[0].amount, 1234569.33);
});

test("no trails or no donors gives no kinds; an unknown status throws", () => {
  assert.deepEqual(sumByTrailStatus([]), []);
  assert.deepEqual(sumByTrailStatus([{ donors: [] }]), []);
  assert.throws(() => sumByTrailStatus([{ donors: [d("mystery", 1)] }]), /unknown trail_status/);
});
