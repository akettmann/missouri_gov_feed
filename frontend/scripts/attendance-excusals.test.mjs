import assert from "node:assert/strict";
import { test } from "node:test";
import { excusalCell, excusalCellFor, recordsExcusals } from "../src/lib/attendance.ts";

// Attendance cells for leave and recusals: only the MO Senate records them (#604).
test("House session: a dash, not 0", () => {
  assert.equal(recordsExcusals("state_house"), false);
  assert.equal(excusalCell("state_house", "0"), "—");
});

test("Congress sessions: a dash, not 0", () => {
  for (const ch of ["us_house", "us_senate"]) assert.equal(excusalCell(ch, "0"), "—");
});

test("Senate session: real numbers, including 0", () => {
  assert.equal(recordsExcusals("state_senate"), true);
  assert.equal(excusalCell("state_senate", "0"), "0");
  assert.equal(excusalCell("state_senate", "3"), "3");
  assert.equal(excusalCell("state_senate", "1.5%"), "1.5%");
});

// The wiring cellText uses: removing the `excusal` branch must fail these.
test("excusalCellFor: flagged columns dash by the row's chamber, others pass through", () => {
  const col = { excusal: true };
  assert.equal(excusalCellFor(col, { chamberId: "state_house" }, "0"), "—");
  assert.equal(excusalCellFor(col, { chamberId: "state_senate" }, "0"), "0");
  assert.equal(excusalCellFor({}, { chamberId: "state_house" }, "0"), "0");
});
