# Diagrams

Every diagram is a PlantUML source (`.puml`) with its rendered SVG next to it. Edit the `.puml`; the
pre-commit hook (`scripts/render_plantuml.py`) re-renders the SVG. When you add a diagram, add it here too.

## Project-wide

### Pipeline

How `mogov run` does a full refresh, from the loaders through dbt to the exports. Source: [pipeline.puml](pipeline.puml)

![Pipeline](pipeline.svg)

### Lineage

Source -> loader -> raw -> intermediate -> marts -> reporting, grouped from the dbt manifest. Source: [lineage.puml](lineage.puml)

![Lineage](lineage.svg)

### Data model

The marts schema: one profile per current Missouri official and the facts keyed to it. Source: [data_model.puml](data_model.puml)

![Data model](data_model.svg)

### Frontend data flow

How the parquet exports become the static site. Source: [frontend_data_flow.puml](frontend_data_flow.puml)

![Frontend data flow](frontend_data_flow.svg)

### Missouri bill flow

How a bill becomes law in the Missouri General Assembly, which the `mo_house` and `mo_senate` records follow.
Source: [mo_bill_flow.puml](mo_bill_flow.puml)

![Missouri bill flow](mo_bill_flow.svg)

## Per source

One flow per loader; [docs/sources.md](../sources.md) describes each source and its quirks.

### bluebook

Missouri Official Manual: judges, county circuits and official bios. Source: [sources/bluebook.puml](sources/bluebook.puml)

![bluebook](sources/bluebook.svg)

### census_tiger

Census TIGER district, county and place boundaries. Source: [sources/census_tiger.puml](sources/census_tiger.puml)

![census_tiger](sources/census_tiger.svg)

### census_zcta

Census Gazetteer ZIP code areas: internal points and land areas for find-by-ZIP. Source: [sources/census_zcta.puml](sources/census_zcta.puml)

![census_zcta](sources/census_zcta.svg)

### congress_legislators

The unitedstates/congress-legislators roster and terms. Source: [sources/congress_legislators.puml](sources/congress_legislators.puml)

![congress_legislators](sources/congress_legislators.svg)

### courtlistener_bulk

CourtListener bulk files: judges and federal judges' financial disclosures. Source: [sources/courtlistener_bulk.puml](sources/courtlistener_bulk.puml)

![courtlistener_bulk](sources/courtlistener_bulk.svg)

### courtlistener_case_bulk

Case history from CourtListener's quarterly bulk files. Source: [sources/courtlistener_case_bulk.puml](sources/courtlistener_case_bulk.puml)

![courtlistener_case_bulk](sources/courtlistener_case_bulk.svg)

### courtlistener_cases

Case history from the CourtListener API, for officials found in stage 1. Source: [sources/courtlistener_cases.puml](sources/courtlistener_cases.puml)

![courtlistener_cases](sources/courtlistener_cases.svg)

### epa_frs

EPA Facility Registry Service, Missouri state file: facilities, owners, and NAICS and SIC codes. Source: [sources/epa_frs.puml](sources/epa_frs.puml)

![epa_frs](sources/epa_frs.svg)

### fec

Federal Election Commission bulk files and API. Source: [sources/fec.puml](sources/fec.puml)

![fec](sources/fec.svg)

### fjc_judges

Federal Judicial Center directory of federal judges. Source: [sources/fjc_judges.puml](sources/fjc_judges.puml)

![fjc_judges](sources/fjc_judges.svg)

### house_fd

U.S. House Clerk financial disclosures. Source: [sources/house_fd.puml](sources/house_fd.puml)

![house_fd](sources/house_fd.svg)

### mec

Missouri Ethics Commission exports (opt-in). Source: [sources/mec.puml](sources/mec.puml)

![mec](sources/mec.svg)

### mo_auditor

Missouri State Auditor audit reports and the performance rating printed in each report. Source: [sources/mo_auditor.puml](sources/mo_auditor.puml)

![mo_auditor](sources/mo_auditor.svg)

### mo_employee_pay

Missouri state payroll from data.mo.gov. Source: [sources/mo_employee_pay.puml](sources/mo_employee_pay.puml)

![mo_employee_pay](sources/mo_employee_pay.svg)

### mo_house

Missouri House XML exports and roll-call PDFs. Source: [sources/mo_house.puml](sources/mo_house.puml)

![mo_house](sources/mo_house.svg)

### mo_senate

Missouri Senate daily journals. Source: [sources/mo_senate.puml](sources/mo_senate.puml)

![mo_senate](sources/mo_senate.svg)

### mo_senate_topics

Missouri Senate topical index of bills. Source: [sources/mo_senate_topics.puml](sources/mo_senate_topics.puml)

![mo_senate_topics](sources/mo_senate_topics.svg)

### openstates_people

The Open States people repo. Source: [sources/openstates_people.puml](sources/openstates_people.puml)

![openstates_people](sources/openstates_people.svg)

### senate_efd

U.S. Senate eFD financial disclosures (opt-in). Source: [sources/senate_efd.puml](sources/senate_efd.puml)

![senate_efd](sources/senate_efd.svg)

### shor_mccarty

Shor-McCarty state legislator ideology scores. Source: [sources/shor_mccarty.puml](sources/shor_mccarty.puml)

![shor_mccarty](sources/shor_mccarty.svg)

### tap_mec

MEC campaign finance via The Accountability Project mirror. Source: [sources/tap_mec.puml](sources/tap_mec.puml)

![tap_mec](sources/tap_mec.svg)

### voteview

Voteview congressional roll calls and DW-NOMINATE scores. Source: [sources/voteview.puml](sources/voteview.puml)

![voteview](sources/voteview.svg)

### wikidata

Wikidata positions, occupations and relatives. Source: [sources/wikidata.puml](sources/wikidata.puml)

![wikidata](sources/wikidata.svg)
