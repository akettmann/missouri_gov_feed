-- The 24-hour-notice dedupe (#156) may only drop "24 Hour" notice rows, and never more than 15% of the notice rows
-- or dollars. Measured October 2026: 134 of 7,698 notice rows (1.7%), 6.4% of notice dollars.
-- See notice_dedupe_violations.
{{ mogov.notice_dedupe_violations(ref('stg_tap_mec__contributions'), ref('int_tap_mec__contributions')) }}
