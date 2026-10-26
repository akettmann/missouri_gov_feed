-- The House's names for its legislative sessions, keyed by the session code every House model carries
-- (251, 253, 183), so the frontend labels sessions the way the House does. One row per session.
select
    session_code,
    session_name,
    session_year,
    session_type,
    general_assembly,
    session_of_general_assembly
from {{ ref('stg_mo_house__sessions') }}
