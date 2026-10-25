import assert from "node:assert/strict";
import { test } from "node:test";
import { query } from "../src/lib/exports/db.ts";

// Values bind to `?` placeholders; a quote or SQL fragment in an id is data, never SQL text.
test("query binds params to ? placeholders, including an in-list", async () => {
  const hostile = "C1'); drop table x; --";
  const ids = ["C1", hostile, "C3"];
  const rows = await query(
    `select v from (values ('C1'), ('${"C1'); drop table x; --".replaceAll("'", "''")}'), ('C2'), ('C3')) t(v)
     where v in (${ids.map(() => "?").join(", ")}) order by v`,
    ids,
  );
  assert.deepEqual(
    rows.map((r) => r.v),
    ["C1", "C1'); drop table x; --", "C3"].sort(),
  );
});

test("query with no params still works", async () => {
  assert.deepEqual(await query("select 1 as n"), [{ n: 1 }]);
});
