import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  expenseYears,
  fiscalYearLabel,
  gapYears,
  groupExpenses,
  showsExpenses,
} from "../src/lib/legislatorExpenses.ts";

const row = (fiscal_year, expense_type, amount, extra = {}) => ({
  fiscal_year,
  expense_type,
  payee_name: "SMITH, JANE A",
  amount,
  match_confidence: "high",
  source_url: `https://data.example/${fiscal_year}.json`,
  ...extra,
});

test("fiscal year label says July to June, not the calendar year", () => {
  assert.equal(fiscalYearLabel(2026), "FY2026 (July 2025 to June 2026)");
});

test("expenseYears keeps one expense type, newest year first", () => {
  const rows = [
    row(2024, "per diem", 8000),
    row(2025, "mileage", 500),
    row(2026, "per diem", 9000),
    row(2025, "per diem", 8500),
  ];
  assert.deepEqual(
    expenseYears(rows, "per diem").map((r) => [r.fiscal_year, r.amount]),
    [
      [2026, 9000],
      [2025, 8500],
      [2024, 8000],
    ],
  );
  assert.deepEqual(
    expenseYears(rows, "mileage").map((r) => r.fiscal_year),
    [2025],
  );
});

test("a member with mileage only has no per diem rows", () => {
  const rows = [row(2023, "mileage", 151.8)];
  assert.equal(expenseYears(rows, "per diem").length, 0);
  assert.equal(expenseYears(rows, "mileage").length, 1);
});

test("gapYears lists years between the first and last row that have no row", () => {
  const years = expenseYears(
    [row(2023, "per diem", 1), row(2026, "per diem", 1), row(2025, "per diem", 1)],
    "per diem",
  );
  assert.deepEqual(gapYears(years), [2024]);
  assert.deepEqual(gapYears([row(2026, "per diem", 1)]), []);
  assert.deepEqual(gapYears([]), []);
});

test("the section shows for a legislature seat, or for anyone with rows, and for no one else", () => {
  assert.equal(showsExpenses("state_house", []), true);
  assert.equal(showsExpenses("state_senate", null), true);
  assert.equal(showsExpenses("us_house", []), false);
  assert.equal(showsExpenses("us_house", null), false);
  assert.equal(showsExpenses("secretary_of_state", [row(2024, "per diem", 1)]), true);
});

test("the footer carries the state's required data-policy disclaimer", () => {
  const layout = readFileSync(new URL("../src/layouts/Layout.astro", import.meta.url), "utf8").replace(
    /\s+/g,
    " ",
  );
  for (const phrase of [
    "has been modified for use from its original source, which is the State of Missouri",
    "THE STATE OF MISSOURI MAKES NO REPRESENTATIONS OR WARRANTY AS TO THE COMPLETENESS, ACCURACY, TIMELINESS, OR CONTENT OF ANY DATA MADE AVAILABLE THROUGH THIS SITE",
    "EXPRESSLY DISCLAIMS ALL WARRANTIES, WHETHER EXPRESS OR IMPLIED, INCLUDING ANY IMPLIED WARRANTIES OF MERCHANTABILITY, OR FITNESS FOR A PARTICULAR PURPOSE",
    "The data is subject to change as modifications and updates are complete",
    "being used at one’s own risk",
  ]) {
    assert.ok(layout.includes(phrase), phrase);
  }
});

test("an empty export is 'not loaded' (null), not an official with no rows", () => {
  assert.equal(groupExpenses([]), null);
  const grouped = groupExpenses([{ official_id: "a", ...row(2026, "per diem", 100) }]);
  assert.ok(grouped instanceof Map);
  assert.equal(grouped.get("b"), undefined); // loaded, but this official has no matched row
  assert.equal(grouped.get("a").length, 1);
  assert.equal("official_id" in grouped.get("a")[0], false);
});
