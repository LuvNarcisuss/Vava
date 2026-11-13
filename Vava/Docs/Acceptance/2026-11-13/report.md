# iPhone function acceptance

Date: November 13, 2026 (Asia/Shanghai)

## Environment and result

Xcode 26.0.1 (17A400) built the Debug source under the former TableTennis project name. The Xcode-signed simulator build was installed and launched on the dedicated Table Tennis UI Acceptance iPhone 17 Pro, iOS 26.0.1, device 3A39D112-678E-4E15-B0AE-A531D5B3167D. The unsigned diagnostic build could open the welcome screen, but could not access Keychain. The signed build reached the live Auth request.

The release-configured navigation is blocked by anonymous signup. A direct request to the bound Supabase project returned HTTP 422, anonymous_provider_disabled. The signed app showed a generic request error and returned the Log in button to its idle state. The catalog contains four short records, six courses, and six replays. The catalog and agreements buckets each contain zero objects.

To exercise the downstream UI, a temporary copy of the current source used a loopback fixture, a distinct Bundle ID, Xcode simulator signing, and the same real video files. The workspace source and cloud settings remained intact. The fixture used local response data and did not simulate Realtime delivery. The publisher replay opened the real external WTT page. Purchases were excluded.

## Observed function coverage

| Surface | Passed in this run | Still open |
| --- | --- | --- |
| Welcome and agreements | Current signed app launched. Unchecked consent prevented entry. Both distinct bundled PDFs opened. Returning preserved the selected state. The local fixture restored its Keychain session after restart. | Real one-tap login and session refresh; public PDFs. The required-consent error remains visible after checking the box. |
| Shorts | Fixture played the Ravne final and Netherlands vs China recordings. Playback position advanced, and pause held the same value. Like and save updated and were retained after reopening. Posted a comment and saw it in the discussion list. Searching Netherlands showed the correct clip and opened its player. The private submission form and system photo picker opened, and the imported video was listed. | Live Storage playback, swipe/mute/share/report UI, reply UI, selecting/transcoding/uploading/reading back a private video. |
| Academy | Six courses displayed. Free lesson opened, checklist advanced from 0/3 to 1/3, and save state changed. The 45-coin lesson displayed its locked state. The zero-balance prompt routed to Wallet. | Successful coin debit and unlock, real-device or cross-device entitlement, course filter and external coaching playback. |
| Watch | Six replay rows displayed. Opened one match detail and saved it. The actual WTT YouTube page for Sun Yingsha vs Wang Manyu showed match footage. | Other five replay playback paths, regional availability, and filter/share/report UI. |
| Chats | Empty invitation state. Looked up a test partner by code, followed, saw Message appear, entered a thread, sent text, and saw it in the thread and inbox preview. | Two real sessions, WebSocket event delivery and reconnect, read/mute/pin/archive and blocking UI. |
| Me | Profile, follower/following counts and collections were visible. Edited and saved name and bio. Saved showed a short, replay and course. Settings and wallet screens opened. Wallet showed zero coins, six unavailable packs and empty activity. | Real media submission and removal, actual account deletion, accessibility modes, avatar editing, and all StoreKit transaction flows. |

## Fresh database evidence

A rollback-only transaction with three disposable identities exercised consent, course/replay counts, hidden unpublished shorts, saved state, practice progress, comment submission, report filtering, mutual-follow restrictions, duplicate message idempotency, participant reads, third-party isolation, and blocked-user revocation. All assertions completed. A separate rolled-back check found that an authenticated fresh identity could read all four steps of the paid forehand course via the course endpoint. Zero fixture identities remained.

## Priorities

1. Enable anonymous sign-in in the bound project and publish the four MP4s and four covers through authenticated Storage administration. Verify the first-run flow and video Range responses with the signed app.
2. Gate paid course content on server-verified ownership before selling coin packs. The device-side lock is visible, while the current course endpoint returns content to an authenticated account without ownership.
3. Refine onboarding feedback. Clear the stale consent error when the checkbox is selected. Surface anonymous-login unavailability with a specific message and keep network retries clear.
4. Run a two-account live chat and private upload acceptance. Verify reconnect behavior, revocation in an already-open thread, and cleanup on account deletion.
5. Improve Shorts on a portrait screen. The landscape match is aspect-fit and leaves substantial space, while its overlaid action rail can obscure play. Use portrait-source framing where rights and composition permit. Refine disabled control contrast and fix singular progress copy such as "1 drills complete."
6. Clean up three source warning categories before migrating to Swift 6: actor-isolated default color, AVAssetExportSession capture, and deprecated button insets.

Static resource verification passed 131 checks, and swift-format strict lint completed with exit zero. No app behavior changes were made during this acceptance round.
