// The names an official's committee filed one donor under, as a sentence fragment: `"A"`, `"A" and "B"`,
// `"A", "B" and "C"`. Built at display time from a list, never stored as a delimited column (#370, #833): a
// filed name can hold commas and semicolons. Pure and import-free so node:test can load it.
export function quotedNames(names: readonly string[]): string {
  const q = names.map((n) => `"${n}"`);
  if (q.length <= 1) return q.join("");
  return `${q.slice(0, -1).join(", ")} and ${q[q.length - 1]}`;
}

/**
 * Whether any listed committee is itself a donor to another listed committee (`donor_mec_committee_id` among
 * the other listed ids), the only case where dollars can show up twice in the summary (#833).
 */
export function trailsGiveToEachOther(
  trails: readonly {
    mec_committee_id: string;
    donors: readonly { donor_mec_committee_id: string | null }[];
  }[],
): boolean {
  const ids = new Set(trails.map((t) => t.mec_committee_id));
  return trails.some((t) =>
    t.donors.some(
      (d) =>
        d.donor_mec_committee_id !== null &&
        d.donor_mec_committee_id !== t.mec_committee_id &&
        ids.has(d.donor_mec_committee_id),
    ),
  );
}
