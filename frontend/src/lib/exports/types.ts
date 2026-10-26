// Shapes of the per-official bundle the build emits (one prerendered page + one JSON per official).
// Column names follow the dbt marts / planned rpt_* contracts so a real export can replace a fixture as-is.

import type { PayVoteRow } from "../attendancePay";
import type { LegislatorExpenseRow } from "../legislatorExpenses";
import type { CommitteeSession } from "../committeePosts";

export type Confidence = string; // 'exact id' | 'exact (MEC crosswalk)' | 'high' | 'medium' | ...

export interface Official {
  official_id: string;
  slug: string;
  full_name: string;
  party: string | null;
  level: string;
  office: string;
  office_title: string | null;
  district: string | null;
  current_term_start: string | null;
  current_term_end: string | null;
  image_url: string | null;
  hometown: string | null;
  email: string | null;
  is_judge_or_lawyer: boolean | null;
}

export interface CoverageItem {
  key: string;
  label: string;
  status: string;
  count: number;
}

export interface Indicator {
  indicator: string;
  value: number | null;
  period: number | null;
  detail: string | null;
  source_url: string | null;
  /** party unity only: the official's own first and last year with a party-line vote in the chamber */
  first_vote_year: number | null;
  last_vote_year: number | null;
  /** party unity only: the first year we hold any party-line vote for that chamber (any official) */
  chamber_data_start_year: number | null;
}

/** rpt_donor_rollup summed per election cycle x donor group (medium matches kept apart for the toggle). */
export interface DonorCycleRow {
  cycle: number;
  donor_group: string;
  match_confidence: Confidence;
  total_amount: number;
  contribution_count: number;
}

/** rpt_donor_rollup's biggest non-individual donors over all years (top 25 per official). */
export interface TopDonorRow {
  donor_name: string;
  donor_group: string;
  match_confidence: Confidence;
  source: string;
  source_url: string | null;
  total_amount: number;
  contribution_count: number;
  first_year: number;
  last_year: number;
}

/** rpt_committee_donors: one donor of a Missouri committee (top 10 non-individual, plus summed individuals). */
export interface CommitteeDonorRow {
  donor_rank: number | null;
  donor_class: string;
  donor_name: string;
  total_amount: number;
  contribution_count: number;
  first_year: number | null;
  last_year: number | null;
  /** mec committee | ambiguous mec name | not an mec filer | end of trail | individuals */
  trail_status: string;
  donor_mec_committee_id: string | null;
}

/**
 * One of the official's committee donors, matched by name to a Missouri committee (rpt_donor_rollup's
 * donor_mec_committee_id), with that committee's own donors. Always a name match: MEC records no donor ID.
 */
export interface CommitteeTrail {
  mec_committee_id: string;
  committee_name: string | null;
  /** the donor's name(s) as the official's committee reported them */
  donor_names: string;
  gave_official: number;
  first_year: number;
  last_year: number;
  /**
   * high = curated alias (a curated alias list, each alias group checked against the committee's filings or its own filed name), committee
   * ID written into the name, or the same name; medium = looser name (abbreviations spelled out,
   * PAC/Fund etc. dropped, or a filer's parenthesized short name)
   */
  link_confidence: string;
  committee_total_amount: number;
  source_url: string;
  donors: CommitteeDonorRow[];
}

/** rpt_gift_rollup rows: official x year x principal x category x confidence x source. */
export interface GiftRollupRow {
  year: number;
  lobbyist_principal: string;
  expenditure_category: string;
  match_confidence: Confidence;
  source: string;
  source_url: string | null;
  total_amount: number;
  gift_count: number;
  lobbyist_count: number;
}

/** `fct_federal_donor_summary` rows (FEC aggregates; real data). */
export interface FederalDonorRow {
  cycle: number;
  aggregate_kind: string;
  bucket: string;
  total: number;
  contribution_count: number | null;
}

export interface CommercialTie {
  tie_kind: string;
  whose: string;
  detail: string;
  as_of_year: number | null;
  source: string;
  source_url: string | null;
}

export interface FamilyTie {
  relation: string;
  relative_name: string | null;
  role: string | null;
  organization: string | null;
  source: string;
  source_url: string | null;
}

export interface DisclosureFiling {
  disclosure_type: string;
  filing_kind: string | null;
  report_year: number | null;
  filing_date: string | null;
  document_url: string | null;
  n_items: number;
}

/** One indicator value placed among its peer group (rpt_indicator_peers), with every peer's value. */
export interface PeerStrip {
  indicator: string;
  peer_group: string;
  detail: string | null;
  chamber: string;
  period: number | null;
  value: number;
  peer_count: number;
  peer_median: number | null;
  republican_median: number | null;
  democratic_median: number | null;
  /** every member of the peer group, the official included */
  peers: { value: number; party: string | null }[];
}

/** rpt_party_breaks: a party-line vote where the official voted against their party's majority. */
export interface PartyBreak {
  chamber: string;
  session_code: string;
  /** the House's name for the session (dim_house_session); null for other chambers or an unlisted session */
  session_name: string | null;
  vote_date: string;
  measure: string | null;
  vote_description: string | null;
  vote_cast: string;
  party_position: string;
  other_party_position: string | null;
  republican_yea: number | null;
  republican_nay: number | null;
  democratic_yea: number | null;
  democratic_nay: number | null;
  source_url: string | null;
}

/** rpt_attendance: one session. */
export interface AttendanceRow {
  chamber: string;
  session_code: string;
  /** the House's name for the session (dim_house_session); null for other chambers or an unlisted session */
  session_name: string | null;
  first_vote_date: string | null;
  last_vote_date: string | null;
  votes_recorded: number;
  votes_present: number;
  absent: number;
  absent_with_leave: number;
  not_voting: number;
  recused_from_voting: number;
  attendance_pct: number;
  chamber_attendance_pct: number;
}

/** fct_case_history: a case the official sat on (judge) or argued (attorney). */
export interface CaseRow {
  role: string;
  case_name: string;
  court: string | null;
  docket_number: string | null;
  date_filed: string | null;
  disposition: string | null;
  publication_status: string | null;
  source_url: string | null;
}

/** rpt_votes_by_subject: roll calls on bills with one subject. */
export interface SubjectVotes {
  chamber: string;
  subject_name: string;
  subject_source: string;
  roll_calls: number;
  yea: number;
  nay: number;
  other: number;
  bills: number;
}

/** rpt_interest_vote_overlap rolled up per industry: money in, and votes on bills touching that industry. */
export interface InterestOverlap {
  industry: string;
  /** cumulative through the latest overlapping vote (the model's amounts are "in or before the vote's year") */
  contributions_amount: number;
  gifts_amount: number;
  first_money_year: number | null;
  last_money_year: number | null;
  match_confidence: string;
  roll_calls: number;
  yea: number;
  nay: number;
  other: number;
  bills: number;
  /** the most recent overlapping votes */
  examples: {
    vote_date: string;
    bill: string;
    short_title: string | null;
    vote_cast: string;
    vote_source_url: string | null;
    bill_source_url: string | null;
  }[];
}

/** A company that gave to the official and has EPA-regulated sites in their area (fct_jurisdiction_businesses). */
export interface DistrictDonor {
  /** the matched contributors as filed, sorted; one string per donor */
  donors: string[];
  /** the official's total from those contributors (all years loaded), not per site */
  donated_amount: number;
  n_contributions: number;
  first_year: number | null;
  last_year: number | null;
  /** about who received the money (medium = tied to the official by name only), not the site match */
  match_confidence: string;
  /** one `<url> <donor name>` line per donor and filing page, built from fct_jurisdiction_business_donors (lib/siteDonors); see parseDonorLinks */
  donor_links: string | null;
  sites: {
    facility_name: string | null;
    address: string | null;
    city: string | null;
    naics_description: string | null;
    /** "same name" or "same company" (a brand from the company_brands seed) */
    matched_by: string;
    frs_url: string | null;
  }[];
}

/** EPA-regulated sites in the official's area per NAICS sector (rpt_district_business_industries). */
export interface DistrictIndustry {
  sector_code: string | null;
  sector_name: string;
  n_sites: number;
  n_donor_sites: number;
}

/** A dataset is either real (from an export) or a labelled stand-in until the dbt model exists. */
export interface Dataset<T> {
  sample: boolean;
  model: string;
  rows: T[];
}

/** One fct_judge_time_to_disposition row: median days from filing to termination of the civil or criminal dockets assigned to a judge. */
export interface TimeToDisposition {
  cl_person_id: string;
  case_type: "civil" | "criminal";
  court_id: string;
  dockets_assigned: number;
  dockets_with_both_dates: number;
  dockets_ends_before_filed: number;
  dockets_measured: number;
  share_with_both_dates: number;
  median_days_to_disposition: number | null;
}

export interface OfficialBundle {
  official: Official;
  coverage: CoverageItem[];
  indicators: Indicator[];
  peers: PeerStrip[];
  voting: {
    status: string;
    /** null when the rpt_* export is missing (section says so instead of showing nothing) */
    party_breaks: PartyBreak[] | null;
    attendance: AttendanceRow[] | null;
    /** rpt_attendance_pay: pay per vote attended by year and in total; null when the export is missing */
    attendance_pay: PayVoteRow[] | null;
    /** the subjects with the most roll calls (top 20) */
    by_subject: SubjectVotes[] | null;
  };
  /** null when the rpt_interest_vote_overlap export is missing */
  overlap: InterestOverlap[] | null;
  /** House committee posts by session, newest first; null when either committee export is missing */
  committees: CommitteeSession[] | null;
  courts: {
    status: string;
    /** federal district judges only (fct_judge_time_to_disposition): one entry per case type the judge has dockets of, civil first; null for everyone else or when the export is missing */
    time_to_disposition: TimeToDisposition[] | null;
    /** cases per filing year and role; null when the export is missing */
    by_year: { year: number; role: string; cases: number }[] | null;
    total: number;
    /** the most recent cases (all of them are in the CourtListener links) */
    recent: CaseRow[];
  };
  money: {
    status: string;
    federal: FederalDonorRow[];
    cycles: Dataset<DonorCycleRow>;
    /** employers of individual donors (rpt_donor_employers, top 20); null when the export is missing */
    employers:
      | {
          employer: string;
          match_confidence: string;
          donor_count: number;
          total_amount: number;
          first_year: number;
          last_year: number;
          source_url: string | null;
        }[]
      | null;
    /** state officials' individual contributions by size (rpt_donor_size); null when the export is missing */
    size: { cycle: number; band_floor: number; match_confidence: string; total_amount: number }[] | null;
    top_donors: Dataset<TopDonorRow>;
    /** committee donors followed one hop back (rpt_committee_donors); null when the export is missing */
    committee_trails: CommitteeTrail[] | null;
  };
  gifts: Dataset<GiftRollupRow>;
  /** per diem and mileage by state fiscal year (fct_legislator_expenses); null when the export is missing or empty (state expenditures not loaded) */
  expenses: LegislatorExpenseRow[] | null;
  /**
   * Businesses in the official's district or city; null when either export is missing. Officials elected
   * statewide (and judges) have no area, so both lists are empty.
   */
  businesses: { donors: DistrictDonor[]; industries: DistrictIndustry[] } | null;
  interests: {
    commercial_ties: CommercialTie[];
    family_ties: FamilyTie[];
    filings: DisclosureFiling[];
    commercial_ties_status: string;
    family_ties_status: string;
    disclosures_status: string;
  };
}

export interface IndexEntry {
  slug: string;
  full_name: string;
  party: string | null;
  level: string;
  office: string;
  office_title: string | null;
  district: string | null;
}

/**
 * One past-year row of the browse list (rpt_officeholders_by_year). Every row links somewhere: the full profile
 * for anyone serving now (has_profile), otherwise their small past-officeholder page. Same slug scheme for both.
 */
export interface PastOfficeholder extends IndexEntry {
  has_profile: boolean;
}

/** One office a past officeholder held, with the years of the roster data in which they held it. */
export interface PastStint {
  office: string;
  office_title: string | null;
  level: string;
  district: string | null;
  party: string | null;
  years: number[];
}

/** A past officeholder without a full profile: what the rosters say and nothing more. */
export interface PastPerson {
  slug: string;
  official_id: string;
  full_name: string;
  party: string | null;
  /** Roster sources behind this person's rows, each with the roster page(s) and the years each covers. */
  sources: RosterSource[];
  stints: PastStint[];
  /** Other pages whose full name is identical once normalized. A pointer only, not a claim of identity. */
  same_name: SameNameLink[];
}

export interface RosterSource {
  source: string;
  links: { url: string | null; years: number[] }[];
}

export interface SameNameLink {
  kind: "current" | "past";
  slug: string;
  full_name: string;
}

/** One EPA-regulated site in a district (fct_jurisdiction_businesses), with the donor match when there is one. */
export interface SiteRow {
  registry_id: string;
  facility_name: string | null;
  address: string | null;
  city: string | null;
  postal_code: string | null;
  naics_description: string | null;
  owner_name: string | null;
  parent_company_name: string | null;
  is_donor: boolean;
  /** "same name" | "same company"; null when no donor matched */
  matched_by: string | null;
  /** donor names as filed, sorted; one string per donor, empty when no donor matched */
  donors: string[];
  match_confidence: "high" | "medium" | null;
  /** where each matched donor's contributions are filed: `<url> <donor name>` lines (lib/siteDonors), see parseDonorLinks */
  donor_links: string | null;
  frs_url: string | null;
}
