-- TAP MEC contributions without the 24-hour notices that a full report itemizes again (#156):
-- stg_tap_mec__contributions keeps every row of the source; everything that totals gifts (committee receipts, donor
-- summaries, the campaign-finance fact) reads this model. See the drop_reitemized_notices macro for the rule.
{{ mogov.drop_reitemized_notices(ref('stg_tap_mec__contributions')) }}
