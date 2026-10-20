// Shapes of the per-official bundle the build emits (one prerendered page + one JSON per official).
// Column names follow the dbt marts / planned rpt_* contracts so a real export can replace a fixture as-is.

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
  first_vote_date: string | null;
  last_vote_date: string | null;
  votes_recorded: number;
  votes_present: number;
  absent: number;
  absent_with_leave: number;
  not_voting: number;
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
  /** the matched contributors as filed, "; "-separated */
  donor_names: string;
  /** the official's total from those contributors (all years loaded), not per site */
  donated_amount: number;
  n_contributions: number;
  first_year: number | null;
  last_year: number | null;
  /** about who received the money (medium = tied to the official by name only), not the site match */
  match_confidence: string;
  contributions_url: string | null;
  sites: {
    facility_name: string | null;
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
    /** the subjects with the most roll calls (top 20) */
    by_subject: SubjectVotes[] | null;
  };
  /** null when the rpt_interest_vote_overlap export is missing */
  overlap: InterestOverlap[] | null;
  courts: {
    status: string;
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
  };
  gifts: Dataset<GiftRollupRow>;
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

/** One past-year row of the browse list (rpt_officeholders_by_year); slug only for people serving now. */
export interface PastOfficeholder extends Omit<IndexEntry, "slug"> {
  slug: string | null;
}
