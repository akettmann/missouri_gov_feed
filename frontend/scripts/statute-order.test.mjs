import assert from "node:assert/strict";
import { test } from "node:test";
import {
  chapterCountsText,
  compareChapters,
  compareSectionIds,
  revisorChapterUrl,
  romanValue,
  sectionNeighbors,
  statuteChapterPath,
  titleAnchor,
} from "../src/lib/statuteText.ts";

const sorted = (ids) => ids.toSorted(compareSectionIds);

test("plain sections sort by the number after the dot as a whole number, as the Revisor lists them", () => {
  // Chapter 456 on revisor.mo.gov (October 2026): ... 456.041, 456.950 ... 456.995, 456.1000 ... 456.1135.
  assert.deepEqual(sorted(["456.1000", "456.995", "456.041", "456.950", "456.1135", "456.001"]), [
    "456.001",
    "456.041",
    "456.950",
    "456.995",
    "456.1000",
    "456.1135",
  ]);
  assert.deepEqual(sorted(["1.1001", "1.110", "1.100", "1.010", "1.190"]), [
    "1.010",
    "1.100",
    "1.110",
    "1.190",
    "1.1001",
  ]);
});

test("Uniform-Code style sections come after the plain ones, by article, then section, then letter", () => {
  assert.deepEqual(
    sorted([
      "456.10-1001",
      "456.4-411B",
      "456.1-101",
      "456.4A-411",
      "456.1135",
      "456.4-412",
      "456.4-411A",
      "456.2-201",
      "456.9-901",
    ]),
    [
      "456.1135",
      "456.1-101",
      "456.2-201",
      "456.4-411A",
      "456.4-411B",
      "456.4-412",
      "456.4A-411",
      "456.9-901",
      "456.10-1001",
    ],
  );
  assert.deepEqual(sorted(["400.3-505", "400.2A-101", "400.2-725", "400.10-101"]), [
    "400.2-725",
    "400.2A-101",
    "400.3-505",
    "400.10-101",
  ]);
});

test("ids from different chapters sort by chapter, a lettered chapter after its plain number", () => {
  assert.deepEqual(sorted(["30A.010", "31.010", "30.999", "1.010", "100.010"]), [
    "1.010",
    "30.999",
    "30A.010",
    "31.010",
    "100.010",
  ]);
  assert.deepEqual(["30A", "100", "30", "9", "31"].toSorted(compareChapters), [
    "9",
    "30",
    "30A",
    "31",
    "100",
  ]);
});

test("the order is total: equal only for the same id, and the same whatever the input order", () => {
  const ids = ["1.010", "1.1001", "30A.010", "400.3-505", "456.4A-411", "456.4-411A", "1.100"];
  const once = sorted(ids);
  assert.deepEqual(sorted(ids.toReversed()), once);
  for (const a of ids) for (const b of ids) assert.equal(compareSectionIds(a, b) === 0, a === b);
});

test("roman numerals", () => {
  assert.equal(romanValue("I"), 1);
  assert.equal(romanValue("IV"), 4);
  assert.equal(romanValue("XXXIV"), 34);
  assert.equal(romanValue("XXXVIII"), 38);
  assert.equal(romanValue("XLI"), 41);
  assert.ok(Number.isNaN(romanValue("Title 1")));
  assert.deepEqual(
    ["XL", "IX", "XLI", "X", "II"].toSorted((a, b) => romanValue(a) - romanValue(b)),
    ["II", "IX", "X", "XL", "XLI"],
  );
});

test("chapter counts say exactly what they count", () => {
  assert.equal(chapterCountsText({ sections: 30, sections_in_force: 12 }), "12 of 30 sections in force");
  assert.equal(chapterCountsText({ sections: 30, sections_in_force: 30 }), "30 sections, all in force");
  assert.equal(chapterCountsText({ sections: 1, sections_in_force: 1 }), "1 section, in force");
  assert.equal(chapterCountsText({ sections: 167, sections_in_force: 0 }), "167 sections, none in force");
  assert.equal(chapterCountsText({ sections: 1, sections_in_force: 0 }), "1 section, none in force");
  assert.equal(
    chapterCountsText({ sections: 1676, sections_in_force: 1200 }),
    "1,200 of 1,676 sections in force",
  );
});

test("neighbors within a chapter, none past either end or for an unknown id", () => {
  const ids = ["1.010", "1.020", "1.030"];
  assert.deepEqual(sectionNeighbors(ids, "1.020"), { prev: "1.010", next: "1.030" });
  assert.deepEqual(sectionNeighbors(ids, "1.010"), { prev: null, next: "1.020" });
  assert.deepEqual(sectionNeighbors(ids, "1.030"), { prev: "1.020", next: null });
  assert.deepEqual(sectionNeighbors(ids, "9.999"), { prev: null, next: null });
});

test("paths, anchors and the Revisor's chapter link", () => {
  assert.equal(statuteChapterPath("30A"), "/statutes/chapter/30A/");
  assert.equal(titleAnchor("XXVI"), "title-xxvi");
  assert.equal(titleAnchor(null), "no-longer-listed");
  assert.equal(revisorChapterUrl("456"), "https://revisor.mo.gov/main/OneChapter.aspx?chapter=456");
});
