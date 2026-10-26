// Assembles one OfficialBundle per official from the exports. Row selection and display shaping only
// (filter to one official, distinct filings, Missouri vs out-of-state, trimming rpt_donor_rollup to what
// a page draws); the real aggregation lives in dbt (rpt_*), with a fixture standing in when one is missing.
import { createHash } from "node:crypto";
import { DONOR_GROUP_SQL } from "../rollups";
import { splitDonorNames } from "../donorLinks";
import { exportedAt, hasExport, query } from "./db";
import { buildCommitteeSessions, type PostCounts, type TitledMembership } from "../committeePosts";
import { payYearsGate, type PayVoteRow } from "../attendancePay";
import { loadLegislatorExpenses } from "./legislatorExpenses";
import { groupPast, linkSameName, type RosterRow } from "./past";
import { sampleDonorCycles, sampleGiftRollup, sampleTopDonors } from "./fixtures";
import type {
  AttendanceRow,
  CaseRow,
  CommercialTie,
  CommitteeDonorRow,
  CommitteeTrail,
  CoverageItem,
  Dataset,
  DisclosureFiling,
  DistrictDonor,
  DistrictIndustry,
  DonorCycleRow,
  FamilyTie,
  FederalDonorRow,
  GiftRollupRow,
  IndexEntry,
  InterestOverlap,
  Indicator,
  Official,
  OfficialBundle,
  PartyBreak,
  PastOfficeholder,
  PastPerson,
  PeerStrip,
  SubjectVotes,
  TimeToDisposition,
  TopDonorRow,
} from "./types";

type ProfileRow = Omit<Official, "slug"> & Record<string, string | number | boolean | null>;

export const COVERAGE: { key: string; label: string }[] = [
  { key: "votes", label: "Votes" },
  { key: "bias", label: "Ideology indicators" },
  { key: "donations", label: "Donations" },
  { key: "disclosures", label: "Financial disclosures" },
  { key: "commercial_ties", label: "Commercial ties" },
  { key: "family_ties", label: "Family ties" },
  { key: "cases", label: "Court cases" },
  { key: "voluntary_disclosures", label: "Voluntary disclosures" },
];
const COUNT_COLUMN: Record<string, string> = { bias: "n_bias_indicators" }; // the rest are n_<key>

export function slugFor(fullName: string, officialId: string): string {
  const name = fullName
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return `${name}-${createHash("sha1").update(officialId).digest("hex").slice(0, 6)}`;
}

function groupBy<T extends { official_id: string }>(rows: T[]): Map<string, Omit<T, "official_id">[]> {
  const out = new Map<string, Omit<T, "official_id">[]>();
  for (const { official_id, ...rest } of rows) {
    const list = out.get(official_id);
    if (list) list.push(rest);
    else out.set(official_id, [rest]);
  }
  return out;
}

const SORT_LEVEL: Record<string, number> = { state: 0, federal: 1, local: 2 };

async function loadAll(): Promise<OfficialBundle[]> {
  const profiles = await query<ProfileRow>(`
    select d.official_id, d.full_name, d.party, d.level, d.office, d.office_title, d.district,
           cast(d.current_term_start as varchar) as current_term_start,
           cast(d.current_term_end as varchar) as current_term_end,
           d.image_url, d.hometown, d.email, p.is_judge_or_lawyer,
           p.* exclude (official_id, full_name, party, level, office, office_title, district, is_judge_or_lawyer)
    from {dim_official} d join {official_profile} p using (official_id)
    order by d.level, d.office, try_cast(d.district as integer), d.district, d.full_name`);

  const indicators = groupBy(
    await query<Indicator & { official_id: string }>(`
      select official_id, indicator, value, period, detail, source_url
      from {fct_bias_indicators} order by indicator, period`),
  );

  // by_employer is ~2.8k rows of individual donors' employers; not used by the MVP pages
  const federal = groupBy(
    await query<FederalDonorRow & { official_id: string }>(`
      select official_id, cycle, aggregate_kind,
             case when aggregate_kind = 'by_state' then
               case when bucket = 'Missouri' then 'Missouri' else 'Out of state' end else bucket end as bucket,
             cast(sum(total) as double) as total, cast(sum(contribution_count) as integer) as contribution_count
      from {fct_federal_donor_summary}
      where aggregate_kind <> 'by_employer'
      group by all order by cycle, aggregate_kind, bucket`),
  );

  const ties = groupBy(
    await query<CommercialTie & { official_id: string }>(`
      select official_id, tie_kind, whose, detail, as_of_year, source, source_url
      from {fct_commercial_ties} where is_latest_report order by tie_kind, whose, detail`),
  );

  const family = groupBy(
    await query<FamilyTie & { official_id: string }>(`
      select official_id, relation, relative_name, role, organization, source, source_url
      from {fct_family_ties} order by relation, organization`),
  );

  const filings = groupBy(
    await query<DisclosureFiling & { official_id: string }>(`
      select official_id, disclosure_type, filing_kind, report_year,
             cast(filing_date as varchar) as filing_date, document_url, cast(count(*) as integer) as n_items
      from {fct_disclosures} group by all order by report_year desc nulls last, filing_date desc nulls last`),
  );

  // rpt_donor_rollup is up to ~7k rows per official (one per donor-year), too big for a page; ship the
  // two views the page draws. Medium matches stay separate so "hide possible matches" can drop them.
  const hasDonors = hasExport("rpt_donor_rollup");
  const realCycles = hasDonors
    ? groupBy(
        await query<DonorCycleRow & { official_id: string }>(`
          select official_id, election_cycle as cycle, ${DONOR_GROUP_SQL} as donor_group,
                 case when match_confidence = 'medium' then 'medium' else 'matched' end as match_confidence,
                 cast(sum(total_amount) as double) as total_amount,
                 cast(sum(contribution_count) as integer) as contribution_count
          from {rpt_donor_rollup}
          group by all order by cycle`),
      )
    : null;
  // individuals are excluded: their donor_name is an employer, and values like 'none' / 'retired' would
  // rank as if they were organizations
  const realTop = hasDonors
    ? groupBy(
        await query<TopDonorRow & { official_id: string }>(`
          select official_id, donor_name, donor_group, match_confidence, source, source_url,
                 total_amount, contribution_count, first_year, last_year
          from (
            select official_id, donor_name, ${DONOR_GROUP_SQL} as donor_group, match_confidence,
                   min(source) as source, min(source_url) as source_url,
                   cast(sum(total_amount) as double) as total_amount,
                   cast(sum(contribution_count) as integer) as contribution_count,
                   cast(min(transaction_year) as integer) as first_year,
                   cast(max(transaction_year) as integer) as last_year,
                   row_number() over (partition by official_id order by sum(total_amount) desc) as rank
            from {rpt_donor_rollup}
            where donor_class <> 'individual'
            group by official_id, donor_name, donor_class, match_confidence
          ) ranked
          where rank <= 25 order by official_id, rank`),
      )
    : null;
  // One hop back: each official's 5 largest committee donors that matched a Missouri committee by name,
  // with that committee's own donors (rpt_committee_donors keeps its top 10 plus summed individuals).
  const TRAILS = 5;
  const hasTrails = hasDonors && hasExport("rpt_committee_donors");
  type TrailRow = Omit<
    CommitteeTrail,
    "donors" | "committee_name" | "committee_total_amount" | "source_url"
  > & {
    official_id: string;
  };
  const trailRows = hasTrails
    ? await query<TrailRow>(`
        select official_id, mec_committee_id, donor_names, gave_official, first_year, last_year, link_confidence
        from (
          select official_id, donor_mec_committee_id as mec_committee_id,
                 string_agg(distinct donor_name, '; ' order by donor_name) as donor_names,
                 cast(sum(total_amount) as double) as gave_official,
                 cast(min(transaction_year) as integer) as first_year,
                 cast(max(transaction_year) as integer) as last_year,
                 -- 'high' < 'medium': the weakest link among the rows shown
                 max(donor_link_confidence) as link_confidence,
                 row_number() over (partition by official_id order by sum(total_amount) desc) as rank
          from {rpt_donor_rollup}
          where donor_mec_committee_id is not null
          group by official_id, donor_mec_committee_id
        ) ranked
        where rank <= ${TRAILS} order by official_id, rank`)
    : [];
  const committeeDonors = new Map<
    string,
    Pick<CommitteeTrail, "committee_name" | "committee_total_amount" | "source_url" | "donors">
  >();
  if (hasTrails && trailRows.length > 0) {
    const ids = [...new Set(trailRows.map((t) => t.mec_committee_id))];
    for (const r of await query<
      CommitteeDonorRow & {
        mec_committee_id: string;
        committee_name: string | null;
        committee_total_amount: number;
        source_url: string;
      }
    >(
      `
      select mec_committee_id, committee_name, cast(committee_total_amount as double) as committee_total_amount,
             source_url, cast(donor_rank as integer) as donor_rank, donor_class, donor_name,
             cast(total_amount as double) as total_amount, cast(contribution_count as integer) as contribution_count,
             first_year, last_year, trail_status, donor_mec_committee_id
      from {rpt_committee_donors}
      where mec_committee_id in (${ids.map(() => "?").join(", ")})
      order by mec_committee_id, donor_rank nulls last`,
      ids,
    )) {
      const { mec_committee_id, committee_name, committee_total_amount, source_url, ...donor } = r;
      const entry = committeeDonors.get(mec_committee_id) ?? {
        committee_name,
        committee_total_amount,
        source_url,
        donors: [],
      };
      entry.donors.push(donor);
      committeeDonors.set(mec_committee_id, entry);
    }
  }
  const trails = hasTrails
    ? groupBy(
        trailRows.flatMap((t) => {
          const hop = committeeDonors.get(t.mec_committee_id);
          return hop ? [{ ...t, ...hop }] : [];
        }),
      )
    : null;

  const realGifts = hasExport("rpt_gift_rollup")
    ? groupBy(
        await query<GiftRollupRow & { official_id: string }>(`
          select official_id, cast(expenditure_year as integer) as year, lobbyist_principal,
                 expenditure_category, match_confidence, source, source_url,
                 cast(total_amount as double) as total_amount, cast(gift_count as integer) as gift_count,
                 cast(lobbyist_count as integer) as lobbyist_count
          from {rpt_gift_rollup} order by year`),
      )
    : null;

  // Voting-record models have no fixture: a missing export renders as "not available yet".
  type PeerRow = Omit<PeerStrip, "peers"> & { official_id: string; party: string | null };
  const peerRows = hasExport("rpt_indicator_peers")
    ? await query<PeerRow>(`
        select official_id, party, indicator, peer_group, chamber, period, detail, value,
               cast(peer_count as integer) as peer_count, peer_median, republican_median, democratic_median
        from {rpt_indicator_peers} where value is not null`)
    : [];
  const peerValues = new Map<string, { value: number; party: string | null }[]>();
  for (const r of peerRows) {
    peerValues.set(r.peer_group, [
      ...(peerValues.get(r.peer_group) ?? []),
      { value: r.value, party: r.party },
    ]);
  }
  const peers = groupBy(
    // the row's own party only feeds peerValues; a strip carries party solely inside its peers list
    peerRows.map(({ party: _party, ...r }) => ({ ...r, peers: peerValues.get(r.peer_group) ?? [] })),
  );

  // The House's own session names (dim_house_session); a missing export or session leaves the label honest ("session code NNN")
  if (!hasExport("dim_house_session")) {
    console.warn(
      "dim_house_session is missing from the exports, so House sessions are labelled by session code instead of the House's session name. Re-export: `uv run mogov build`, then `uv run mogov export --format parquet`.",
    );
  }
  const houseSessionNames = new Map<string, string>(
    hasExport("dim_house_session")
      ? (
          await query<{ session_code: string; session_name: string }>(
            `select session_code, session_name from {dim_house_session}`,
          )
        ).map((r) => [r.session_code, r.session_name])
      : [],
  );
  const withSessionName = <T extends { chamber: string; session_code: string }>(rows: T[]) =>
    rows.map((r) => ({
      ...r,
      session_name: r.chamber === "state_house" ? (houseSessionNames.get(r.session_code) ?? null) : null,
    }));

  const breaks = hasExport("rpt_party_breaks")
    ? groupBy(
        await query<PartyBreak & { official_id: string }>(`
          select official_id, chamber, session_code, cast(vote_date as varchar) as vote_date, measure,
                 vote_description, vote_cast, party_position, other_party_position,
                 cast(republican_yea as integer) as republican_yea, cast(republican_nay as integer) as republican_nay,
                 cast(democratic_yea as integer) as democratic_yea, cast(democratic_nay as integer) as democratic_nay,
                 source_url
          from {rpt_party_breaks} order by vote_date desc`),
      )
    : null;

  const attendance = hasExport("rpt_attendance")
    ? groupBy(
        await query<AttendanceRow & { official_id: string }>(`
          select official_id, chamber, session_code,
                 cast(first_vote_date as varchar) as first_vote_date,
                 cast(last_vote_date as varchar) as last_vote_date,
                 cast(votes_recorded as integer) as votes_recorded, cast(votes_present as integer) as votes_present,
                 cast(absent as integer) as absent, cast(absent_with_leave as integer) as absent_with_leave,
                 cast(not_voting as integer) as not_voting,
                 cast(recused_from_voting as integer) as recused_from_voting, attendance_pct, chamber_attendance_pct
          from {rpt_attendance} order by first_vote_date`),
      )
    : null;

  const attendancePay = hasExport("rpt_attendance_pay")
    ? groupBy(
        await query<PayVoteRow & { official_id: string }>(`
          select official_id, chamber, period, cast(calendar_year as integer) as calendar_year,
                 cast(voting_years as integer) as voting_years, cast(covered_years as integer) as covered_years,
                 cast(votes_recorded as integer) as votes_recorded, cast(votes_attended as integer) as votes_attended,
                 cast(pay_amount as double) as pay_amount, pay_basis, match_confidence, pay_source_url, dollars_per_vote_attended
          from {rpt_attendance_pay} order by calendar_year`),
      )
    : null;

  type EmployerRow = OfficialBundle["money"]["employers"] & object;
  const employers = hasExport("rpt_donor_employers")
    ? groupBy(
        await query<EmployerRow[number] & { official_id: string }>(`
          select official_id, employer, match_confidence, cast(donor_count as integer) as donor_count,
                 cast(total_amount as double) as total_amount, first_year, last_year, source_url
          from (
            select *, row_number() over (partition by official_id order by total_amount desc, employer) as rank
            from {rpt_donor_employers}
          ) ranked
          where rank <= 20 order by official_id, rank`),
      )
    : null;

  type SizeRow = OfficialBundle["money"]["size"] & object;
  const sizes = hasExport("rpt_donor_size")
    ? groupBy(
        await query<SizeRow[number] & { official_id: string }>(`
          select official_id, election_cycle as cycle, band_floor, match_confidence,
                 cast(total_amount as double) as total_amount
          from {rpt_donor_size} order by cycle, band_floor`),
      )
    : null;

  // up to ~700 subjects per legislator; the page lists the 20 with the most roll calls
  const subjects = hasExport("rpt_votes_by_subject")
    ? groupBy(
        await query<SubjectVotes & { official_id: string }>(`
          select official_id, chamber, subject_name, subject_source,
                 cast(roll_calls as integer) as roll_calls, cast(yea as integer) as yea,
                 cast(nay as integer) as nay, cast(other as integer) as other, cast(bills as integer) as bills
          from (
            select *, row_number() over (partition by official_id order by roll_calls desc, subject_name) as rank
            from {rpt_votes_by_subject}
          ) ranked
          where rank <= 20 order by official_id, rank`),
      )
    : null;

  // rpt_interest_vote_overlap has one row per (vote, industry), ~2k per legislator: roll up per industry.
  // Its money is cumulative ("in or before the vote's year"), so the latest row's amount is the total, and
  // that row's match_confidence is the weakest of all the money counted.
  const hasOverlap = hasExport("rpt_interest_vote_overlap");
  type OverlapRow = Omit<InterestOverlap, "examples"> & { official_id: string };
  const overlapRows = hasOverlap
    ? await query<OverlapRow>(`
        select official_id, industry,
               cast(max(contributions_amount) as double) as contributions_amount,
               cast(max(gifts_amount) as double) as gifts_amount,
               min(first_money_year) as first_money_year, max(last_money_year) as last_money_year,
               arg_max(match_confidence, vote_date) as match_confidence,
               cast(count(distinct vote_id) as integer) as roll_calls,
               cast(count(distinct case when vote_cast = 'yea' then vote_id end) as integer) as yea,
               cast(count(distinct case when vote_cast = 'nay' then vote_id end) as integer) as nay,
               cast(count(distinct case when vote_cast not in ('yea', 'nay') then vote_id end) as integer) as other,
               cast(count(distinct bill) as integer) as bills
        from {rpt_interest_vote_overlap}
        group by official_id, industry
        order by official_id, max(contributions_amount) + max(gifts_amount) desc`)
    : [];
  const examples = new Map<string, InterestOverlap["examples"]>();
  if (hasOverlap) {
    for (const r of await query<
      InterestOverlap["examples"][number] & { official_id: string; industry: string }
    >(`
      select official_id, industry, cast(vote_date as varchar) as vote_date, bill, short_title, vote_cast,
             vote_source_url, bill_source_url
      from (
        select *, row_number() over (partition by official_id, industry order by vote_date desc, bill) as rank
        from {rpt_interest_vote_overlap}
      ) ranked
      where rank <= 5`)) {
      const { official_id, industry, ...ex } = r;
      const key = `${official_id}|${industry}`;
      examples.set(key, [...(examples.get(key) ?? []), ex]);
    }
  }
  const overlap = groupBy(
    overlapRows.map((r) => ({ ...r, examples: examples.get(`${r.official_id}|${r.industry}`) ?? [] })),
  );

  // A U.S. House district holds up to ~10k EPA sites: ship only the ones tied to a donor (a few hundred at
  // most), grouped under their donor, plus the per-sector counts. A site's donor columns repeat the totals
  // for its set of donors, so rows sharing donor_name_list carry the same amount, years and links.
  const hasBusinesses =
    hasExport("fct_jurisdiction_businesses") && hasExport("rpt_district_business_industries");
  const districtDonors = new Map<string, DistrictDonor[]>();
  if (hasBusinesses) {
    type SiteRow = Omit<DistrictDonor, "donors" | "sites"> &
      DistrictDonor["sites"][number] & { official_id: string; donor_name_list: string };
    const byDonor = new Map<string, DistrictDonor>();
    for (const r of await query<SiteRow>(`
      select official_id, donor_name_list, cast(donated_amount as double) as donated_amount,
             cast(n_contributions as integer) as n_contributions, first_year, last_year, match_confidence,
             donor_links, facility_name, city, naics_description, matched_by, frs_url
      from {fct_jurisdiction_businesses} where is_donor
      order by official_id, donated_amount desc, donor_name_list, facility_name, city`)) {
      const {
        official_id,
        donor_name_list,
        facility_name,
        city,
        naics_description,
        matched_by,
        frs_url,
        ...donor
      } = r;
      // the raw list is a chr(31)-joined string: split it here and key on it, but never ship it
      const key = `${official_id}|${donor_name_list}`;
      let group = byDonor.get(key);
      if (!group) {
        group = { ...donor, donors: splitDonorNames(donor_name_list), sites: [] };
        byDonor.set(key, group);
        districtDonors.set(official_id, [...(districtDonors.get(official_id) ?? []), group]);
      }
      group.sites.push({ facility_name, city, naics_description, matched_by, frs_url });
    }
  }
  const districtIndustries = hasBusinesses
    ? groupBy(
        await query<DistrictIndustry & { official_id: string }>(`
          select official_id, sector_code, sector_name, cast(n_sites as integer) as n_sites,
                 cast(n_donor_sites as integer) as n_donor_sites
          from {rpt_district_business_industries}
          order by official_id, sector_code is null, n_sites desc, sector_name`),
      )
    : null;

  // House committee posts: counts from fct_committee_posts, committee names from the titled memberships only
  const committeeSessions =
    hasExport("fct_committee_posts") && hasExport("fct_committee_memberships")
      ? buildCommitteeSessions(
          await query<PostCounts>(`
            select official_id, session_code, cast(session_year as integer) as session_year,
                   cast(committees_held as integer) as committees_held, cast(chair_posts as integer) as chair_posts,
                   cast(vice_chair_posts as integer) as vice_chair_posts,
                   cast(co_chair_posts as integer) as co_chair_posts, cast(ranking_posts as integer) as ranking_posts
            from {fct_committee_posts}`),
          await query<TitledMembership>(`
            select official_id, session_code, committee_name, position_name, is_subcommittee
            from {fct_committee_memberships} where position_name <> 'Member'`),
          process.env,
          console.warn,
          houseSessionNames,
          new Set(
            (
              await query<{ session_code: string }>(
                `select distinct session_code from {fct_committee_memberships} where source = 'committee_list'`,
              )
            ).map((r) => r.session_code),
          ),
        )
      : null;

  // a federal appellate judge has ~6k cases: ship yearly counts plus the most recent ones
  const RECENT_CASES = 50;
  const hasCases = hasExport("fct_case_history");
  const caseYears = hasCases
    ? groupBy(
        await query<{ official_id: string; year: number; role: string; cases: number }>(`
          select official_id, cast(extract(year from date_filed) as integer) as year, role,
                 cast(count(*) as integer) as cases
          from {fct_case_history} where date_filed is not null
          group by all order by year`),
      )
    : null;
  const caseTotals = hasCases
    ? new Map(
        (
          await query<{ official_id: string; n: number }>(`
            select official_id, cast(count(*) as integer) as n from {fct_case_history} group by 1`)
        ).map((r) => [r.official_id, r.n]),
      )
    : new Map<string, number>();
  const recentCases = hasCases
    ? groupBy(
        await query<CaseRow & { official_id: string }>(`
          select official_id, role, case_name, court, docket_number, cast(date_filed as varchar) as date_filed,
                 disposition, publication_status, source_url
          from (
            select *, row_number() over (partition by official_id order by date_filed desc nulls last) as rank
            from {fct_case_history}
          ) ranked
          where rank <= ${RECENT_CASES} order by official_id, rank`),
      )
    : null;

  const expenses = await loadLegislatorExpenses();
  // federal district judges: one row per CourtListener judge, joined to the official by official_id
  const dispositions = hasExport("fct_judge_time_to_disposition")
    ? new Map(
        (
          await query<TimeToDisposition & { official_id: string }>(`
            select official_id, cl_person_id, court_id, cast(dockets_assigned as integer) as dockets_assigned,
                   cast(dockets_with_both_dates as integer) as dockets_with_both_dates,
                   cast(dockets_ends_before_filed as integer) as dockets_ends_before_filed,
                   cast(dockets_measured as integer) as dockets_measured,
                   share_with_both_dates, median_days_to_disposition
            from {fct_judge_time_to_disposition} where official_id is not null`)
        ).map((r) => [r.official_id, r]),
      )
    : new Map<string, TimeToDisposition>();

  return profiles
    .sort((a, b) => (SORT_LEVEL[a.level] ?? 9) - (SORT_LEVEL[b.level] ?? 9))
    .map((p): OfficialBundle => {
      const id = p.official_id;
      const status = (k: string) => String(p[`${k}_status`]);
      const coverage: CoverageItem[] = COVERAGE.map(({ key, label }) => ({
        key,
        label,
        status: status(key),
        count: Number(p[COUNT_COLUMN[key] ?? `n_${key}`] ?? 0),
      }));
      const donates = Number(p.n_donations) > 0;
      const cycles: Dataset<DonorCycleRow> = realCycles
        ? { sample: false, model: "rpt_donor_rollup", rows: (realCycles.get(id) ?? []) as DonorCycleRow[] }
        : { sample: true, model: "rpt_donor_rollup", rows: donates ? sampleDonorCycles(id) : [] };
      const topDonors: Dataset<TopDonorRow> = realTop
        ? { sample: false, model: "rpt_donor_rollup", rows: (realTop.get(id) ?? []) as TopDonorRow[] }
        : { sample: true, model: "rpt_donor_rollup", rows: donates ? sampleTopDonors(id) : [] };
      const gifts: Dataset<GiftRollupRow> = realGifts
        ? { sample: false, model: "rpt_gift_rollup", rows: (realGifts.get(id) ?? []) as GiftRollupRow[] }
        : {
            sample: true,
            model: "rpt_gift_rollup",
            rows: Number(p.n_lobbyist_gifts) > 0 ? sampleGiftRollup(id) : [],
          };
      return {
        official: {
          official_id: id,
          slug: slugFor(p.full_name, id),
          full_name: p.full_name,
          party: p.party,
          level: p.level,
          office: p.office,
          office_title: p.office_title,
          district: p.district,
          current_term_start: p.current_term_start,
          current_term_end: p.current_term_end,
          image_url: p.image_url,
          hometown: p.hometown,
          email: p.email,
          is_judge_or_lawyer: p.is_judge_or_lawyer,
        },
        coverage,
        indicators: (indicators.get(id) ?? []) as Indicator[],
        peers: (peers.get(id) ?? []) as PeerStrip[],
        voting: {
          status: status("votes"),
          party_breaks: breaks ? (withSessionName(breaks.get(id) ?? []) as PartyBreak[]) : null,
          attendance: attendance ? (withSessionName(attendance.get(id) ?? []) as AttendanceRow[]) : null,
          attendance_pay: attendancePay ? ((attendancePay.get(id) ?? []) as PayVoteRow[]) : null,
          by_subject: subjects ? ((subjects.get(id) ?? []) as SubjectVotes[]) : null,
        },
        overlap: hasOverlap ? ((overlap.get(id) ?? []) as InterestOverlap[]) : null,
        committees: committeeSessions ? (committeeSessions.get(id) ?? []) : null,
        courts: {
          status: status("cases"),
          time_to_disposition: dispositions.get(id) ?? null,
          by_year: caseYears
            ? ((caseYears.get(id) ?? []) as { year: number; role: string; cases: number }[])
            : null,
          total: caseTotals.get(id) ?? 0,
          recent: (recentCases?.get(id) ?? []) as CaseRow[],
        },
        money: {
          status: status("donations"),
          federal: (federal.get(id) ?? []) as FederalDonorRow[],
          cycles,
          size: sizes ? ((sizes.get(id) ?? []) as SizeRow) : null,
          employers: employers ? ((employers.get(id) ?? []) as EmployerRow) : null,
          top_donors: topDonors,
          committee_trails: trails ? ((trails.get(id) ?? []) as CommitteeTrail[]) : null,
        },
        gifts,
        expenses: expenses ? (expenses.get(id) ?? []) : null,
        businesses: districtIndustries
          ? {
              donors: districtDonors.get(id) ?? [],
              industries: (districtIndustries.get(id) ?? []) as DistrictIndustry[],
            }
          : null,
        interests: {
          commercial_ties: (ties.get(id) ?? []) as CommercialTie[],
          family_ties: (family.get(id) ?? []) as FamilyTie[],
          filings: (filings.get(id) ?? []) as DisclosureFiling[],
          commercial_ties_status: status("commercial_ties"),
          family_ties_status: status("family_ties"),
          disclosures_status: status("disclosures"),
        },
      };
    });
}

/**
 * Fails the build when an official's pay-per-vote year rows do not add up to the dbt total, which means
 * rpt_attendance and rpt_attendance_pay were exported from different builds: the years label would be wrong.
 */
function assertPayYearsConsistent(bundles: OfficialBundle[]): OfficialBundle[] {
  const bad = payYearsGate(bundles, process.env, console.warn);
  if (bad.length) {
    const shown = bad.slice(0, 20).map((m) => `  ${m}`);
    throw new Error(
      `Pay per vote: year rows do not match the dbt total for ${bad.length} official(s); rebuild and ` +
        `re-export rpt_attendance and rpt_attendance_pay together (mogov build, mogov export), or set ` +
        `MOGOV_SKIP_PAY_YEARS_CHECK=1 to build anyway.` +
        ["", ...shown].join("\n"),
    );
  }
  return bundles;
}

let cache: Promise<OfficialBundle[]> | undefined;

/** Every official's bundle; computed once per build and shared by pages and JSON endpoints. */
export function allOfficials(): Promise<OfficialBundle[]> {
  cache ??= loadAll().then(assertPayYearsConsistent);
  return cache;
}

export async function officialIndex(): Promise<IndexEntry[]> {
  return (await allOfficials()).map(({ official: o }) => ({
    slug: o.slug,
    full_name: o.full_name,
    party: o.party,
    level: o.level,
    office: o.office,
    office_title: o.office_title,
    district: o.district,
  }));
}

/**
 * The browse list's look-back: past years of rpt_officeholders_by_year (its latest year is the one serving now,
 * which the page takes from dim_official), newest first. Null without the export, so the page lists today only.
 *
 * Single source of truth for where a past name links: every row gets a slug. People serving now (has_profile) get
 * their profile's slug; everyone else gets slugFor(name, official_id), the same scheme, served by a small
 * past-officeholder page at the same /officials/<slug>/ path. `people` holds those small pages' data.
 */
export async function pastOfficeholders(): Promise<{
  currentYear: number;
  years: Map<number, PastOfficeholder[]>;
  people: PastPerson[];
} | null> {
  if (!hasExport("rpt_officeholders_by_year")) return null;
  const slugs = new Map((await allOfficials()).map(({ official: o }) => [o.official_id, o.slug]));
  const rows = await query<RosterRow>(`
    select year, official_id, has_profile, full_name, party, level, office, office_title, district, source, source_url
    from {rpt_officeholders_by_year}
    order by year desc, level, office, try_cast(district as integer), district, full_name`);
  const currentYear = Math.max(...rows.map((r) => r.year));
  // rows are newest first, so a person's first row carries their latest name
  const { years, people } = groupPast(rows, currentYear, slugs, slugFor);
  linkSameName(
    people,
    (await allOfficials()).map(({ official: o }) => ({ full_name: o.full_name, slug: o.slug })),
  );
  return { currentYear, years, people };
}

/** Export timestamps shown on the methodology page as data freshness. */
export function freshness(): { table: string; exported_at: string | null; sample: boolean }[] {
  const tables = [
    "dim_official",
    "official_profile",
    "fct_bias_indicators",
    "fct_federal_donor_summary",
    "fct_commercial_ties",
    "fct_family_ties",
    "fct_disclosures",
    "rpt_donor_rollup",
    "rpt_committee_donors",
    "rpt_gift_rollup",
    "rpt_indicator_peers",
    "rpt_party_breaks",
    "fct_committee_posts",
    "fct_committee_memberships",
    "rpt_attendance",
    "rpt_attendance_pay",
    "dim_house_session",
    "rpt_votes_by_subject",
    "rpt_interest_vote_overlap",
    "fct_jurisdiction_businesses",
    "rpt_district_business_industries",
    "rpt_officeholders_by_year",
  ];
  return tables.map((t) => ({
    table: t,
    exported_at: exportedAt(t)?.toISOString() ?? null,
    sample: (t === "rpt_donor_rollup" || t === "rpt_gift_rollup") && !hasExport(t),
  }));
}
