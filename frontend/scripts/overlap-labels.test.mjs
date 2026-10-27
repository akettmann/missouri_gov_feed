import assert from "node:assert/strict";
import { test } from "node:test";
import { mostRecentBillsLabel, recusedCell, voteLinkLabel } from "../src/lib/overlapLabels.ts";

test("one example reads singular, several plural", () => {
  assert.equal(mostRecentBillsLabel(1), "1 most recent bill");
  assert.equal(mostRecentBillsLabel(5), "5 most recent bills");
});

test("recusals listed beyond the recent bills are named in the label (#154)", () => {
  assert.equal(mostRecentBillsLabel(5, 1), "5 most recent bills + 1 recusal");
  assert.equal(mostRecentBillsLabel(5, 3), "5 most recent bills + 3 recusals");
  assert.equal(mostRecentBillsLabel(0, 2), "2 recusals");
  assert.equal(mostRecentBillsLabel(5, 0), "5 most recent bills");
});

test("Senate journal PDFs are labeled as the day's journal, House votes as roll call", () => {
  assert.equal(
    voteLinkLabel("https://www.senate.mo.gov/22info/Journals/RDay45-2022.pdf#vote3"),
    "Senate journal for that day",
  );
  assert.equal(
    voteLinkLabel("https://www.senate.mo.gov/22info/Journals/RDay45-2022.pdf"),
    "Senate journal for that day",
  );
  assert.equal(
    voteLinkLabel("https://documents.house.mo.gov/billtracking/bills221/rollcalls/055.011.pdf"),
    "roll call",
  );
  assert.equal(voteLinkLabel(null), "roll call");
});

test("recused cell: a count for Senate rows, a dash where the source records none (#154)", () => {
  assert.equal(recusedCell(3), "3");
  assert.equal(recusedCell(0), "0");
  assert.equal(recusedCell(null), "\u2014");
});
