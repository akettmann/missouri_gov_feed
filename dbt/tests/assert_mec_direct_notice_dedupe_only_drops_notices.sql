{{ config(enabled=var('mec_direct', false)) }}
-- The 24-hour-notice dedupe (#156) on the MEC direct export: only "24 Hour" notice rows may be dropped, never more than
-- 15% of the notice rows or dollars. Measured October 2026: 78 of 2,000 notice rows (3.9%), 3.4% of notice dollars.
-- See notice_dedupe_violations.
{{ mogov.notice_dedupe_violations(ref('stg_mec__contributions'), ref('int_mec__contributions_direct')) }}
