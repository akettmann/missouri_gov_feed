import assert from "node:assert/strict";
import { test } from "node:test";
import { sumByTrailStatus, sumGaveOfficial } from "../src/lib/trailSummary.ts";

const d = (trail_status, total_amount) => ({ trail_status, total_amount });

test("sums dollars by status, each donor row once, in a fixed order", () => {
  const trails = [
    { donors: [d("individuals", 100), d("end of trail", 250), d("mec committee", 40)] },
    {
      donors: [
        d("end of trail", 750),
        d("not an mec filer", 5),
        d("ambiguous mec name", 1),
        d("own name", 7),
      ],
    },
  ];
  assert.deepEqual(sumByTrailStatus(trails), [
    { kind: "end of trail", amount: 1000, rows: 2 },
    { kind: "not an mec filer", amount: 5, rows: 1 },
    { kind: "own name", amount: 7, rows: 1 },
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

test("gave-official sums what the listed committees gave the official, not donor dollars", () => {
  const trails = [
    { gave_official: 0.1, donors: [d("end of trail", 1000000)] },
    { gave_official: 0.2, donors: [d("individuals", 5000000)] },
    { gave_official: 108199.7, donors: [] },
  ];
  assert.equal(sumGaveOfficial(trails), 108200);
  // 0.07 * 100 is 7.000000000000001: only rounding each amount to whole cents makes the sum exactly 0.21
  assert.equal(
    sumGaveOfficial([
      { gave_official: 0.07, donors: [] },
      { gave_official: 0.14, donors: [] },
    ]),
    0.21,
  );
  assert.equal(sumGaveOfficial([]), 0);
});
