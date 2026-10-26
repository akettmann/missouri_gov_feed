import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionLabel } from "../src/lib/format.ts";
import {
  COMMITTEE_LIST_NOTE,
  COMMITTEE_LIST_URL,
  buildCommitteeSessions,
  positionLabel,
} from "../src/lib/committeePosts.ts";

const post = (official_id, session_code, extra = {}) => ({
  official_id,
  session_code,
  session_year: 2000 + Number(session_code.slice(0, 2)),
  committees_held: 3,
  chair_posts: 0,
  vice_chair_posts: 0,
  co_chair_posts: 0,
  ranking_posts: 0,
  ...extra,
});
const mem = (official_id, session_code, committee_name, position_name, is_subcommittee = false) => ({
  official_id,
  session_code,
  committee_name,
  position_name,
  is_subcommittee,
});

const NAMES = new Map([
  ["251", "2025 Regular Session"],
  ["253", "2025 1st Extraordinary Session"],
  ["254", "2025 2nd Extraordinary Session"],
]);

test("House sessions are labelled with the House's own names, and a missing name is honest", () => {
  assert.equal(sessionLabel("state_house", "253", NAMES.get("253")), "2025 1st Extraordinary Session");
  assert.equal(sessionLabel("state_house", "261", undefined), "session code 261");
  assert.equal(sessionLabel("state_house", "261", ""), "session code 261");
});

test("committee sessions are named from the names map; the committee list note shows only for list sessions", () => {
  const out = buildCommitteeSessions(
    [post("a", "251"), post("a", "253")],
    [],
    {},
    () => {},
    NAMES,
    new Set(["253"]),
  );
  const [s253, s251] = out.get("a");
  assert.equal(s253.label, "2025 1st Extraordinary Session");
  assert.equal(s253.note, COMMITTEE_LIST_NOTE);
  assert.equal(s251.label, "2025 Regular Session");
  assert.equal(s251.note, null);
});

test("a session the House has not named is labelled by its code, never a guessed ordinal", () => {
  const out = buildCommitteeSessions([post("a", "261")], []);
  assert.equal(out.get("a")[0].label, "session code 261");
});

test("ranking minority member reads as words, the others as listed", () => {
  assert.equal(positionLabel("Ranking Minority Member"), "Ranking minority member");
  assert.equal(positionLabel("Vice-Chair"), "Vice-Chair");
});

test("titles are ordered chair, co-chair, vice-chair, ranking; subcommittees last; sessions newest first", () => {
  const posts = [
    post("a", "251", { chair_posts: 1 }),
    post("a", "261", { chair_posts: 1, vice_chair_posts: 1, ranking_posts: 1, co_chair_posts: 1 }),
    post("b", "261"),
  ];
  const memberships = [
    mem("a", "251", "Budget", "Chair"),
    mem("a", "261", "Rules", "Ranking Minority Member"),
    mem("a", "261", "Appropriations", "Chair"),
    mem("a", "261", "Elections", "Vice-Chair"),
    mem("a", "261", "Joint Panel", "Co-Chair"),
    mem("a", "261", "Budget Subcommittee on X", "Chair", true),
  ];
  const out = buildCommitteeSessions(posts, memberships);
  const a = out.get("a");
  assert.deepEqual(
    a.map((s) => s.session_code),
    ["261", "251"],
  );
  assert.deepEqual(
    a[0].titles.map((t) => `${t.position}|${t.committee}|${t.subcommittee}`),
    [
      "Chair|Appropriations|false",
      "Co-Chair|Joint Panel|false",
      "Vice-Chair|Elections|false",
      "Ranking Minority Member|Rules|false",
      "Chair|Budget Subcommittee on X|true",
    ],
  );
  assert.equal(a[1].label, "session code 251");
  assert.deepEqual(out.get("b")[0].titles, []);
});

test("the newest session links the committee list (no zip yet); older ones link their session zip", () => {
  const out = buildCommitteeSessions([post("a", "251"), post("a", "261")], []);
  const [newest, older] = out.get("a");
  assert.equal(newest.is_latest, true);
  assert.equal(newest.source_url, COMMITTEE_LIST_URL);
  assert.equal(older.is_latest, false);
  assert.equal(older.source_url, "https://documents.house.mo.gov/xml/251.zip");
});

test("subcommittee titles do not count toward the committee totals check", () => {
  const out = buildCommitteeSessions(
    [post("a", "261", { chair_posts: 1 })],
    [mem("a", "261", "Budget", "Chair"), mem("a", "261", "Sub", "Chair", true)],
  );
  assert.equal(out.get("a")[0].titles.length, 2);
});

test("exports from different builds are refused", () => {
  assert.throws(
    () =>
      buildCommitteeSessions([post("a", "261", { chair_posts: 2 })], [mem("a", "261", "Budget", "Chair")]),
    /disagree/,
  );
});

test("MOGOV_SKIP_COMMITTEE_POSTS_CHECK=1 (exactly) bypasses the mismatch throw and logs it", () => {
  const posts = [post("a", "261", { chair_posts: 2 })];
  const mems = [mem("a", "261", "Budget", "Chair")];
  const logs = [];
  const out = buildCommitteeSessions(posts, mems, { MOGOV_SKIP_COMMITTEE_POSTS_CHECK: "1" }, (m) =>
    logs.push(m),
  );
  assert.equal(out.get("a")[0].titles.length, 1);
  assert.equal(logs.length, 1);
  assert.throws(
    () => buildCommitteeSessions(posts, mems, { MOGOV_SKIP_COMMITTEE_POSTS_CHECK: "true" }),
    /uv run mogov export/,
  );
});
