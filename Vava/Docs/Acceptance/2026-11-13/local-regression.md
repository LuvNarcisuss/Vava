# Vava function acceptance

November 13, 2026, Asia/Shanghai

The latest workspace source built in Debug and Release for the simulator with Xcode 26.0.1 (17A400). The Debug app `im.seex.sao2` was installed and launched on Vava UI Acceptance, iPhone 17 Pro, iOS 26.0.1 (23A8464), device `C6BBDAF1-EF03-4F2E-980F-CB8C472367D6`. The first selected tab was Academy. The Release simulator artifact reports Bundle ID `com.vava.pingpong`.

Twelve distinct XCTest UI cases passed across the main run and targeted reruns. Early failures included selectors for localized system controls and timing around system sheets. The successful runs used the same app source and assets as the workspace with a temporary Debug Bundle ID to isolate purchases and deletion from existing simulator data. The simulator's original preferred text size was restored. One bundled video and one bundled image were seeded into the simulator Photos library.

| Area | Observed coverage |
| --- | --- |
| Welcome and agreements | Entry was blocked with unchecked consent. Both agreement links opened in the system browser and both public PDF exports returned HTTP 200. Accepting consent opened Academy. Restart restored the signed-in state. |
| Shorts | The first clip advanced, held its playback position when paused, and resumed. Vertical paging reached the second recording. Search opened the brothers and outdoors recordings. The share sheet opened. Likes and saves persisted across restart and appeared in Me. Refresh advanced to another recording. |
| Comments and publishers | Editorial notes appeared. Adding a private comment and a reply increased the displayed count from 26 to 28. Follow, publisher draft, block, unblock, and local report hiding were exercised. |
| Academy | Free filter, search, save, practice completion, Tutorials progress readback, list refresh, and the insufficient-balance Wallet route passed. A 45-coin unlock exposed the paid drills. |
| Watch | Search opened a replay. The publisher browser and share sheet opened. The replay persisted in the Saved filter after restart. Hiding removed it from that filter. |
| Chats | Invalid contact details were rejected. Saving a contact and draft worked, and reopening restored the draft. Mail was unavailable in the simulator and the app preserved the draft. |
| Me and Settings | Name and bio survived a restart. A Photos image was saved as a local JPEG avatar and read back from the test app's container. Media credits opened. Sign-out survived restart. Deleting the isolated profile reset consent, wallet and contacts. |
| Imported work | Selected a 38-second bundled video from Photos, saved the prepared copy, opened playback, and removed the work. |
| Wallet | Nine Xcode StoreKit offers returned prices. Native cancellation created no wallet entry. Pending and declined purchases left the wallet empty. A verified purchase credited 400 coins, a course unlock debited 45, and restart showed 355 coins with one purchase entry. |
| Accessibility layout | Accessibility Medium produced one column of coin packs and vertically arranged profile collections. |

## Findings

- The welcome screen retains the “Accept the agreements to continue.” error after the checkbox is selected. Continuing still opens Academy.
- Tutorials displays “1 drills complete” for a single completion.
- The Watch hide confirmation labels a replay as “Hide this video.”

The follow-up source changes clear the consent warning when the checkbox is selected, use singular wording for one completed drill, and use replay-specific copy in the Watch hide confirmation. The original findings above describe the tested build.

## Coverage limits

Apple sandbox and production checkout, a configured Mail compose flow, external replay playback, and VoiceOver were outside the observed coverage. The test exercised one successful local coin pack transaction and loaded prices for all nine. It did not exercise the purchase failure injection path or repeat delivery of the same transaction.

The static verifier passed 536 checks. Strict Swift format lint and plist validation passed. Both build configurations emitted existing warnings for actor isolation, AVAssetExportSession sendability and deprecated button insets.
