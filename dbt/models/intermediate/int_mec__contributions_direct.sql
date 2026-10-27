{{ config(enabled=var('mec_direct', false)) }}
-- MEC direct-export contributions without the 24-hour notices that a full report itemizes again (#156): the same
-- pattern as the TAP mirror (int_tap_mec__contributions). See the drop_reitemized_notices macro for the rule.
{{ mogov.drop_reitemized_notices(ref('stg_mec__contributions')) }}
