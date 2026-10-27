import assert from "node:assert/strict";
import { test } from "node:test";
import {
  mixedChamberNote,
  mostRecentBillsLabel,
  recusedCell,
  voteLinkLabel,
} from "../src/lib/overlapLabels.ts";

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

test("recused cell: senate-only plain number, mixed rows name their Senate roll calls, House-only dash", () => {
  assert.equal(recusedCell(2, 10, 10), "2");
  assert.equal(recusedCell(0, 39, 444), "0 of 39 Senate");
  assert.equal(recusedCell(null, 0, 12), "\u2014");
});

test("two-chamber sentence appears only for a mixed row and quotes that row's numbers", () => {
  const senate = { recused: 1, senate_roll_calls: 4, roll_calls: 4 };
  const house = { recused: null, senate_roll_calls: 0, roll_calls: 7 };
  const mixed = { recused: 0, senate_roll_calls: 12, roll_calls: 30 };
  assert.equal(mixedChamberNote([]), null);
  assert.equal(mixedChamberNote([senate, senate]), null);
  assert.equal(mixedChamberNote([house]), null);
  assert.equal(mixedChamberNote([senate, house]), null);
  const note = mixedChamberNote([senate, mixed]);
  assert.match(note, /served in both chambers/);
  assert.match(note, /"0 of 12 Senate"/);
  assert.doesNotMatch(note, /39/);
});
