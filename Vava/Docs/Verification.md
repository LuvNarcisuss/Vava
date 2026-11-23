# Verification record

## November 23 native Swift acceptance

Built the Debug Vava scheme from `Vava.xcodeproj` with Xcode 26.3 (17C529) for the iPhone 17 Pro named **Vava QA**. XCTest reported iOS 26.3.1 (23D8133). The production-source Debug build uses `im.seex.sao2`. All purchases, content changes and callback replays used separate acceptance bundle identifiers on that simulator.

- A course author's profile crashed when UIKit activated the Follow and Message equal-width constraint before the two buttons had a common ancestor. The shared action row now attaches both controls before activating the constraint. The UI regression opened the coaching profile, conversation and profile link, returned to Academy, opened Watch and saved a replay.
- UI checks covered the agreement gate, bundled logo, lesson search and saving, Shorts search, playback controls, likes, comments, video submission, source and license details, hide confirmation, the Chats inbox and nearby discovery, profile collections, settings, profile editing, blocked publishers, media credits and call preview controls. The disabled login button now uses a dark background and light text. [Simulator screenshots](Evidence/SwiftQA-2026-11-23.jpg)
- The isolated StoreKit host initially returned zero products. The simulator logged that the host was not installed for development. A signed Debug simulator host with `get-task-allow` allowed StoreKit Test to change its configuration. The catalog regression exercised zero, one and all nine valid products through the app's StoreKit 1 requests.
- A local purchase credited 400 coins once. Cancellation preserved the ledger bytes. Replaying the purchased callback 12 times, then reopening the wallet and delivering it again, preserved the same 400-coin balance, single entry and ledger bytes.
- All three wallet tests passed together on the final source. The hosted UIKit case tapped the real login, profile, coin pack and Buy controls with StoreKit Test controlling the transaction responses. It verified the success and cancellation alerts, one new activity row and the updated balance on returning to Me.
- A separate XCUITest exercised the visible Xcode purchase sheet. It started with 800 test coins, selected the 400-coin pack at $0.99, confirmed the system purchase and acknowledged the Xcode receipt alert. It opened checkout again, closed the sheet, verified Vava's cancellation message and returned to Me with 1,200 coins and just one additional purchase row.
- The original Debug application's library and wallet JSON inventories were empty before and after testing on this simulator. The installed executable, Debug library and compiled assets matched the final build by SHA-256. The original application was brought back to the foreground at its login screen. Apple sandbox, production payment processing and two-device calls were outside this local run.

## November 16 wallet feedback and Tutorials repair

Me now refreshes on wallet changes, failed delivery has persistent feedback and an explicit retry, and Tutorials describes learning instead of publishing. The pre-fix UI failures were reproduced. Four targeted tests and all 17 existing acceptance cases passed after the repair, including real storage-write failure and recovery, all nine local packs, and app/device restarts. The original 800-coin wallet and personal data were preserved. See [repair validation](Acceptance/2026-11-16/wallet-feedback-repair.md).

## November 16 full function rerun

See [full regression](Acceptance/2026-11-16/full-regression.md) for 17 distinct UI cases, all nine local coin pack purchases, failure and deferred-approval checks, app and simulator restarts, and preservation of the original 800-coin wallet. One test synchronization failure was corrected and rerun successfully; no app source changes were required in this rerun.

## November 16 wallet launch-mode repair

See [wallet regression](Acceptance/2026-11-16/wallet-regression.md) for the reproduced pre-fix failure, local transaction recovery, purchase persistence, cancellation and course-debit regression, and current Debug/Release build results. Apple sandbox and production checkout remain unverified.

## Local static checks

- Ran XcodeGen to generate the iPhone-only project and its shared Debug Run / Release Archive scheme.
- Parsed the Info.plist and generated project settings with plutil. Parsed the scheme XML and checked its target settings and resource references.
- Ran swift-format syntax and style lint on the UIKit source. Compilation, typechecking, simulator launch, device testing and previews were outside the granted scope.
- Ran Scripts/verify_static.py. It checked 131 resource, file hash, source mapping, supported destination, catalog, product configuration and project metadata assertions.
- Reviewed representative frames of the four real clips. FFprobe identified H.264 for all four transcodes. Six publisher thumbnail URLs returned HTTP 200 and image/jpeg. Full publisher playback was not run in the app.
- Reviewed the 22 individual transparent control glyphs at source and control scales, two backgrounds and the opaque launcher artwork. Regenerated the pause glyph to remove the visible background haze. Reviewed the rendered English agreement drafts.

## Supabase deployment

- Table Tennis iOS is active in the 139 organization. Its legacy Toli project is INACTIVE after pause. Permanent deletion remains outstanding.
- Confirmed the private schema, public message RLS, Realtime publication, two public-read buckets and one private bucket. The authenticated role has no direct message insert. The anonymous database role cannot execute bootstrap.
- In one rollback-only SQL transaction, three isolated identities exercised the authenticated role. Verified agreement acceptance, six courses and six replays, unpublished short hiding, save and progress readback, comments and report filtering, mutual-follow requirement, duplicate-message idempotency, participant message visibility, non-member isolation and block revocation. Verified zero fixture identities remained.
- Security Advisor reports authenticated SECURITY DEFINER functions. These are intentional RPC boundaries with pinned empty search paths and scoped access checks. The diagnostic is not a clean production-security certification.
- Anonymous sign-up returned HTTP 422 with anonymous_provider_disabled. An Auth sign-in, WebSocket exchange, private storage request and phone flow were not verified. No temporary write function was deployed. Catalog videos/covers and public agreement PDFs await authenticated upload.

## Remaining release acceptance

iPhone build and layout, anonymous login/restore, two-account Realtime exchange and reconnect, private media authorization and account deletion, editorial media publication, agreement identity/contact and public reads, Apple catalog setup and verified purchases in the appropriate Apple environments. The display name, registered Bundle ID and signing are pending.

## November 13 iPhone acceptance

The current source built and ran on the dedicated iPhone 17 Pro simulator. See [function acceptance](Acceptance/2026-11-13/report.md) for the signed app, isolated UI fixture, live database results, and skipped purchase coverage.

## November 13 Vava identity and public Storage change

- Verified the generated Debug and Release Bundle ID is com.vava.pingpong. The source has no Keychain API calls and stores the session atomically with iOS file protection and backup exclusion.
- Database readback found all three Storage buckets public, zero anonymous write policies, and zero agreement objects. The dashboard still reported Table Tennis iOS for the same reference.
- A rolled-back database probe rejected the old consent revision, accepted and restored the new revision, and checked the submission consent gate before and after acceptance.
- Both PDFs matched the editable English sources, and the rendered one-page layouts were inspected. The public URLs returned HTTP 400 JSON pending upload.
- Ran 139 static checks, parsed the plists and project metadata, and ran strict Swift source lint. Build and native runtime verification were outside this turn's scope.

## Local asset cutover

- The former project contained zero Storage objects, Auth users, and messages. All 16 catalog records and six sets of course exercises matched the checked-in sources.
- Verified local hashes, references, and resource placement for four MP4s, four short covers, six publisher replay covers, original art, fonts and the bundled catalog. The source contains no active Supabase API or media URLs.
- Extracted both revised one-page PDFs, matched their text against the editable sources, and inspected their rendered layouts.
- Ran 147 static checks, plist parsing and strict Swift syntax lint. No app build, launch, payment or runtime test was performed for this cutover.
- Permanent deletion was not verified. See Integration.md for the dashboard access blocker.

## Nine-tier StoreKit catalog

- Ran `Scripts/verify_static.py` with 525 checks. The nine product IDs, reference USD prices, and coin quantities match the integration table and display order. The two new tiers have rates between their neighboring packs.
- Ran strict Swift source lint on `Wallet.swift` and `WalletScreen.swift`, parsed the project and app plists, and checked the shared scheme's Apple catalog setting.
- Build, on-device layout, local StoreKit Test, Apple sandbox, and production purchases were not run. App Store Connect catalog setup and signing are pending verification.

## Local StoreKit availability repair

- The reported wallet state corresponded to an empty eligible product catalog. The shared scheme had no local StoreKit configuration, and transaction delivery excluded `.xcode`.
- Regenerated the project and shared scheme. The static verifier confirmed all nine local consumables match the wallet mapping, the fixture stays outside app resources, Debug Run selects the isolated wallet, and Release uses the Apple transaction policy. Ran strict Swift source lint on the wallet and screen.
- Build, installation, Simulator launch, and StoreKit purchase runs were outside the granted scope. App Store Connect product status, Apple sandbox, and production purchases remain unverified.

## Debug signing and Bundle ID

- Regenerated the project with `im.seex.sao2` for Debug and `com.vava.pingpong` for Release. The configured Yu Sun team ID is `JPTS6M4T5B`.
- Passed 536 static checks. Built Debug using Xcode 26.0.1 and verified `im.seex.sao2` in the built Info.plist. The simulator artifact uses ad-hoc signing.
- Xcode launched Debug on `Vava UI Acceptance`, iPhone 17 Pro, iOS 26.0. First launch reached the agreement screen.
