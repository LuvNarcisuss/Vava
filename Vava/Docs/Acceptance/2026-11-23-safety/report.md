# Report and block acceptance — November 23, 2026

## Scope and environment

Reviewed the current `ios-app-bulid` reports/blocking, relationships, comments, Chats and acceptance requirements. Preserved the app's native UIKit implementation, account-specific library and unrelated authentication/signing work.

- Device: Vava QA, iPhone 17 Pro, iOS 26.3.
- UDID: `96CE1822-AB11-4741-9421-4BEF863DAF77`.
- Unit harness: `com.vava.walletacceptance.swift4f43101c`.
- UI harness: `com.vava.walletacceptance.swift593c54ee`.
- Simulator SDK: iOS 26.2 from the selected Xcode installation.
- All simulator jobs ran serially without cloned destinations. Tests used isolated account UUIDs and separate application containers. The UI fixture opens local test data directly; it does not certify network login.

## Corrections

- Committed report/block state refreshes loaded content screens. Active report IDs are an independent visibility reason and survive reload.
- Reported playback is removed, direct hidden lesson/player/comment routes are filtered, and an open comment sheet clears/closes when its content becomes hidden.
- Successful blocks return to the originating tab root, refresh it and show one dismissible confirmation. Cancel/failure/unblock preserve their routes.
- Blocked nearby people and editorial publishers appear in Settings > Blocked accounts with confirmed long-press and tap-based undo.
- Blocked conversations are excluded from reads without deleting underlying history. Unrelated conversations remain accessible.
- Report withdrawal and unblock remain independent in both orders. Independent manual hiding is also preserved.
- Optional local audit events retain successful report, withdrawal, block and unblock actions after undo. They are not a server operator inbox.
- Failed reports preserve the selected reason and expose Retry. Failed writes and failed undo do not publish changed visibility or append successful audit events.
- A supplemental playback assertion reproduced a stalled replacement clip after dismissing block success: its slider remained at `0%` for eight seconds. The success dialog now explicitly informs Shorts after dismissal so its existing playback gate resumes eligible playback without replacing the player or overriding a manual pause.

## Executed coverage

The final data suite covers eight cases: loaded-screen propagation; both undo orders with retained favorites/audit; chat hiding/restoration without deletion; account isolation and independent manual hiding; self/unknown/hidden target rejection; report/block save failures and retry; failed withdrawal/unblock and retry; and hidden detail/comment/player routes.

The UI suite exercises actual buttons, long presses, dialogs, cold restart, search, saved collections and tab navigation: Academy block cancel/confirm; Shorts profile block and long-press unblock; Chats-origin block; lesson report/restart/long-press withdrawal; video report/search/saved/withdrawal; compact wallet layout; failed report/retry; and failed block/error/current-route retention.

Final coverage is **8 data tests and 10 distinct UI cases, all passing**. The full UI run executed 8 tests with 0 failures. After the playback correction, all three profile-origin block cases passed again, including actual progress advancement. The final route run passed 3 cases: lesson-detail block, Shorts-menu block with advancing playback, and video report/search/saved/undo with advancing replacement playback. Repeated executions are not counted as extra distinct cases. Earlier screenshot-only checks did not catch the stalled playback; its failed run is retained as diagnostic evidence.

| Skill requirement | Current outcome |
| --- | --- |
| Report hides only the targeted content across lists, search, saves and restart | Verified for local lesson/video records; favorites are retained for eligible restoration. |
| Hidden direct routes and open playback/comments | Verified filtering; a supplemental playback test caught and drove repair of the block-alert resume issue. |
| Report and block undo in either order | Verified, including failed undo and separate manual hiding. |
| Block returns to originating root and alerts once after refresh | Verified from Academy, Shorts and Chats profiles, lesson details and the Shorts menu; cancel and failed writes keep the current route. |
| Settings long-press undo with confirmation and accessible tap alternative | Verified native long-press menus and confirmation flows. |
| Preserve history, reject invalid/self targets, isolate accounts | Verified with two isolated account libraries, retained chat/favorite data and rejected mutations. |
| Failed report retains selection and offers retry | Verified by an actual unwritable file path and UI retry without false success. |
| Durable operator inbox and server enforcement | Not implemented. Only account-local audit events and local safety enforcement exist. |
| Other members' private comment moderation and two-device enforcement | Not certified; current comments are local self-authored entries/editorial notes, and real nearby transport needs physical-device coverage. |

The original application's Application Support file set and SHA-256 hashes were unchanged. See `owner-data-verification.json`. All 13 safety-related production source files match the UI test snapshot (normalizing only the isolated app entry-point annotation); see `source-manifest.json`.

## Evidence

- Unit results: `/tmp/vava-safety-unit-final.xcresult` and `/tmp/vava-safety-unit-final.log`.
- UI results: `/tmp/vava-safety-ui-final.xcresult` and `/tmp/vava-safety-ui-final.log`.
- Earlier six-case UI results: `/tmp/vava-safety-ui.xcresult`.
- Reproduced playback failure: `/tmp/vava-safety-playback.xcresult`.
- Corrected three-origin block rerun: `/tmp/vava-safety-block-final.xcresult` (3 tests, 0 failures, including advancing video progress).
- Final detail/menu/report playback run: `/tmp/vava-safety-routes-final.xcresult` (3 tests, 0 failures).
- [Refreshed Academy block confirmation](academy-block-confirmation.png).
- [Filtered Chats inbox](filtered-chat-inbox.png).
- [Unblock keeps the management route](unblock-management.png).
- [Restored lesson](restored-lesson.png).
- [Restored saved video](restored-saved-video.png).
- [Compact wallet balance](compact-wallet.png). The safety fixture has no active StoreKit catalog; unavailable prices in this capture are not a purchase test result.
- [Failed report with Retry](failed-report-retry.png).
- [Failed block remains on the profile](failed-block-profile.png).

## Remaining boundaries

- Reports, blocks and their audit events remain local safety persistence. Server report writes, server-side moderation authorization, private operator queues, review staffing and staff alert delivery are not implemented or verified by this work.
- Comments currently comprise private self-authored entries and bundled editorial notes, not other members' remote/private-profile comments. Private-author server moderation is not certified.
- Nearby transport, block propagation between two physical iPhones and live authentication were not tested. No messages or staff alerts were sent.
- Apple sandbox/production purchases, large-text/VoiceOver/Reduce Motion and production distribution signing were outside this acceptance run.
- The full static verifier still stops at the pre-existing Debug signing-team mismatch (`DEVELOPMENT_TEAM` is empty in the generated Debug setting). Simulator compilation succeeds; this does not establish device/distribution signing readiness.
- Existing formatting warnings in unrelated authentication/call code remain outside this change. Modified safety files, test sources, Ruby harness syntax and whitespace are checked separately.
