// House committee posts per official and session (fct_committee_posts for the counts, fct_committee_memberships
// for the committee names). Pure helpers so the labels are tested on fixed rows.
import { sessionLabel } from "./format.ts";

/** One session's committee work for one member, as the profile shows it. */
export interface CommitteeSession {
  session_code: string;
  session_year: number;
  /** the House's own name ("2025 Regular Session", "2025 1st Extraordinary Session"); "session code NNN" if unnamed */
  label: string;
  /** true for the newest session in the data, the newest session loaded */
  is_latest: boolean;
  /** committees served on: every non-subcommittee entry, so special, joint and conference committees count */
  committees_held: number;
  /** titles held, in a fixed order: chair, co-chair, vice-chair, ranking minority member */
  titles: { position: string; committee: string; subcommittee: boolean }[];
  source_url: string;
  /** a caveat about how this session's committees were sourced, or null */
  note: string | null;
}

export interface PostCounts {
  official_id: string;
  session_code: string;
  session_year: number;
  committees_held: number;
  chair_posts: number;
  vice_chair_posts: number;
  co_chair_posts: number;
  ranking_posts: number;
}

export interface TitledMembership {
  official_id: string;
  session_code: string;
  committee_name: string;
  position_name: string;
  is_subcommittee: boolean;
}

/** The House's own committee list; stands in for the XML zip of a session that has none yet. */
export const COMMITTEE_LIST_URL = "https://house.mo.gov/CommitteeList.aspx";

const POSITION_ORDER = ["Chair", "Co-Chair", "Vice-Chair", "Ranking Minority Member"];

/**
 * Sessions with no member pages take their committees from the House's committee list, which has no co-chair
 * seats and (in 253) fewer committees than the neighbouring regular sessions: no Conference Committee on
 * Budget, no property tax special committees.
 */
export const COMMITTEE_LIST_NOTE =
  "Built from the House's committee list, because the House has no member pages for this session. The list carries no co-chair seats, so a co-chair title may be missing, and it can name fewer committees than the sessions around it.";

export function positionLabel(position: string): string {
  return position === "Ranking Minority Member" ? "Ranking minority member" : position;
}

/** MOGOV_SKIP_COMMITTEE_POSTS_CHECK skips the check only when it is exactly "1" (like MOGOV_SKIP_PAY_YEARS_CHECK). */
export function skipCommitteePostsCheck(env: Record<string, string | undefined>): boolean {
  return env.MOGOV_SKIP_COMMITTEE_POSTS_CHECK === "1";
}

/**
 * Per official, newest session first. Throws when the titled memberships do not add up to the counts in
 * fct_committee_posts (the two exports come from different builds).
 */
export function buildCommitteeSessions(
  posts: PostCounts[],
  memberships: TitledMembership[],
  env: Record<string, string | undefined> = {},
  log: (msg: string) => void = () => {},
  /** House session names by session code (dim_house_session) */
  names: ReadonlyMap<string, string> = new Map(),
  /** session codes whose committees came from the committee list rather than member pages */
  listSessions: ReadonlySet<string> = new Set(),
): Map<string, CommitteeSession[]> {
  const skip = skipCommitteePostsCheck(env);
  if (skip)
    log("MOGOV_SKIP_COMMITTEE_POSTS_CHECK=1: skipping the committee posts vs memberships consistency check.");
  const latest = posts.reduce((m, p) => (p.session_code > m ? p.session_code : m), "");
  const titled = new Map<string, TitledMembership[]>();
  for (const m of memberships) {
    const key = `${m.official_id}|${m.session_code}`;
    titled.set(key, [...(titled.get(key) ?? []), m]);
  }
  const out = new Map<string, CommitteeSession[]>();
  for (const p of posts) {
    const rows = titled.get(`${p.official_id}|${p.session_code}`) ?? [];
    const full = rows.filter((r) => !r.is_subcommittee);
    const count = (position: string) => full.filter((r) => r.position_name === position).length;
    const expected = {
      Chair: p.chair_posts,
      "Vice-Chair": p.vice_chair_posts,
      "Co-Chair": p.co_chair_posts,
      "Ranking Minority Member": p.ranking_posts,
    };
    for (const [position, n] of Object.entries(expected)) {
      if (!skip && count(position) !== n) {
        throw new Error(
          `fct_committee_posts and fct_committee_memberships disagree for ${p.official_id} session ${p.session_code}: ${n} ${position} posts vs ${count(position)} (exports from different builds). Rebuild and re-export: \`uv run mogov build\` then \`uv run mogov export --format parquet\`, or set MOGOV_SKIP_COMMITTEE_POSTS_CHECK=1 (exactly 1) to build anyway.`,
        );
      }
    }
    const titles = rows
      .filter((r) => POSITION_ORDER.includes(r.position_name))
      .map((r) => ({
        position: r.position_name,
        committee: r.committee_name,
        subcommittee: r.is_subcommittee,
      }))
      .sort(
        (a, b) =>
          Number(a.subcommittee) - Number(b.subcommittee) ||
          POSITION_ORDER.indexOf(a.position) - POSITION_ORDER.indexOf(b.position) ||
          a.committee.localeCompare(b.committee),
      );
    const session: CommitteeSession = {
      session_code: p.session_code,
      session_year: p.session_year,
      label: sessionLabel("state_house", p.session_code, names.get(p.session_code)),
      is_latest: p.session_code === latest,
      committees_held: p.committees_held,
      titles,
      source_url:
        p.session_code === latest
          ? COMMITTEE_LIST_URL
          : `https://documents.house.mo.gov/xml/${p.session_code}.zip`,
      note: listSessions.has(p.session_code) ? COMMITTEE_LIST_NOTE : null,
    };
    out.set(p.official_id, [...(out.get(p.official_id) ?? []), session]);
  }
  for (const list of out.values()) list.sort((a, b) => b.session_code.localeCompare(a.session_code));
  return out;
}
