# TODO List

## High priority
"State roll calls are loaded for 2023–2026 by default. Widen the window with MOGOV_HOUSE_SESSIONS (House PDFs go back to 2014) and MOGOV_SENATE_YEARS." Unify this control, make the default 10 years
Add progress logging to the loaders
Review loaders against the guidelines in CLAUDE.md
review the MEC loader it is slower than I would like. Review what takes the most time, and consider if there are any optimizations that can be made

## Medium priority
add diagrams using PlantUML that describe the data model
add diagrams using PlantUML that describe each source and loader's uniqueness
Build case history from CourtListener's quarterly bulk files instead of the REST API (the account token is capped at 125 requests/day across all endpoints). Load opinion-clusters, search_opinioncluster_panel and dockets from the public S3 bucket (same as courtlistener_bulk), filtered to Missouri courts (mo, moctapp*, moed, mowd, ca8), and feed fct_case_history with judges/panel, attorneys and disposition. Trade-off: several GB per quarter, cases up to 3 months stale. Keep the API loader for small top-ups.
## Low priority
add metrics for the loaders
Build Github workflow to run tests, lint, etc
