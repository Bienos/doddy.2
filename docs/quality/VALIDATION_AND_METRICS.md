# Behavioural validation and minimal metrics
## Two separate funnels
**Character/media funnel:** impressions → viewers → retained engaged viewers → qualified app curiosity (survey/direct opt-in) → actual installs. Likes/views never count as app retention or product-market fit.
**App funnel:** install → first *real* capture → successful search → later-date *spontaneous* recall → repeat task on multiple days → preference over user's existing tool → validated price/action willingness.

## Events (no raw user text)
`app_started, memory_save_requested, memory_save_succeeded, memory_save_failed, memory_recall_requested, memory_recall_hit, memory_recall_miss, memory_correction_succeeded, memory_deleted, export_succeeded, ai_request_failed, tool_confirmation_shown, tool_receipt_verified, privacy_session_started`. Event properties: whitelist `{schemaVersion, relativeDayBucket, screen, localeBucket, resultKind, latencyBucket, errorCategory}`. No memory IDs, names, note content, full query, audio, provider responses or user identifiers in analytics by default.

## Metric definitions
- First capture conversion = distinct consenting/new users who verified one saved record / eligible new users.
- Retrieval activation = distinct users retrieving an existing personally saved record / distinct users who saved, same defined observation window.
- **Spontaneous later retrieval** = user-initiated recall on a later calendar day without study prompt / eligible captured users.
- Week-2 retained utility = users who independently complete a valuable task in week 2 / eligible cohort who passed activation.
- Substitute advantage = paired participant preference + observed task completion and effort vs current Notes/Reminders/Siri setup.
- Verified reminder rate = receipts with actual confirmed native write / confirmed write attempts; unknown outcomes reported separately.
- Gross/contribution economics by actual billed usage; do not transpose public industry medians into revenue projections.

## Proposed protocol
Recruit 20–24 adults as an initial **test size proposal**; use screened real recent saving/recall episodes, no solely founder friends. Mixed qualitative interviews and two-week diary; randomized (where possible) clear/no-character variants that share *same actual utility*. Compare against each person's strongest existing alternative. Pre-register threshold decisions before testing. Capture failures, lost data concerns, setup time and privacy objections. Obtain appropriate informed research consent and retention/deletion policy before collecting any identifiable recordings.

## Research gaps to complete
D03 Voice of Customer and D04 competitor/substitute evaluation have not been found as accepted work in the inventoried material. Implement these prior to costly scale. Source: all-in-one D01/D05 reports and strategic recommendations in `reference/compiled_research/`.
