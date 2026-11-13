# Verification record

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
