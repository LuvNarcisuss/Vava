# Local H5 presentation

The current Vava interface is a local H5 application. React Native initializes a native WKWebView, extracts the bundled `vava.zip`, and opens its local `index.html`. Every product route, including welcome, five independent tab stacks, details, comments, profile forms, wallet, chat and call controls, renders as HTML elements and CSS through React Native for Web. There is no remote website or downloaded executable update.

`ReactNative/App.tsx` is the native shell. `ReactNative/WebApp.tsx` and the existing screen modules are the shared presentation source compiled for the browser. `Web/platform.tsx` supplies browser dialogs, local image mapping and refresh gestures. `Web/native.web.tsx` renders HTML video and received call frames. `Web/bridge.ts` transports typed commands and snapshots through the shell to the existing `VavaNative` module. Web pages do not create a second library, account store or wallet in localStorage.

The on-device session opens after the user checks the agreement box and taps Log in. Cold starts and sign-outs display that screen. Native StoreKit, Photos selection, sharing, source browsing, persistence, microphone/camera and encrypted nearby transport keep their current ownership and identifiers.

## Build and package

Install locked dependencies with `npm ci`. After changing presentation sources run `npm run build:web`, which emits the production browser bundle and creates the deterministic `Assets/LocalWeb/vava.zip`. The archive includes HTML, JavaScript, CSS, raster glyphs and licensed fonts; its manifest records source hashes. It has no dependency on Metro, a CDN or an HTTP server. React Native Debug normally uses Metro for the small native shell; Release embeds that shell in the application. The isolated acceptance host also embeds it to verify offline startup.

After changing native file membership, run `xcodegen generate` and `pod install`. ZIPFoundation 0.9.20 extracts the app-owned archive. Both the generator and generated project include the archive and WKWebView bridge. Preserve the existing app identity, signing and iPhone-only destinations.

Run `npm run typecheck`, `npx tsc -p tsconfig.web.json`, and `python3 Scripts/verify_static.py` when their required owner authorization exists. The static verifier checks archive freshness. Compilation, launches and runtime tests require owner authorization.

## Resource and bridge boundaries

WKWebView uses a nonpersistent website data store and an individual cache export directory. It may read only that directory. The archive rejects symlinks and traversal paths before extraction. Native snapshots copy only supported media fields from bundle media or the existing imported-video directory. Library JSON, wallet files and originals are never exposed or relocated. Signing out or changing accounts clears exported media. Browser navigation stays on the local entry; publisher and agreement links use the original native browser command. Content Security Policy disallows remote scripts, network requests, frames and form submission.

Only the main local frame can send commands. The React Native host allows known commands, validates message shape, correlates responses and ignores repeated IDs. Acknowledged component properties carry outgoing messages, avoiding legacy view-registry lookups under Fabric. Native services still validate every operation and transaction. Snapshot revisions retain ordering protection. Web process failure offers a retry; backgrounding pauses HTML video and the original native lifecycle suspends communication.

## Acceptance boundary

The owner authorized compilation and checks on Vava UI Acceptance for this migration. `Tests/prepare_h5_acceptance.rb` generates a distinct app identifier and an embedded JavaScript host. `Tests/LocalH5Tests.swift` exercises the actual WKWebView and bridge inside that application. Original wallet and library files must remain unchanged. Record the fresh run results separately from the preceding React Native and wallet acceptance records. Nearby calls still require two physical iPhones, and local StoreKit tests do not establish Apple sandbox or production readiness.

References: [React Native for Web setup](https://necolas.github.io/react-native-web/docs/setup/), [Apple local file loading](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:)), and [ZIPFoundation](https://github.com/weichsel/ZIPFoundation).

## Verified on November 16, 2026

The final source built and ran on **Vava UI Acceptance**, iPhone 17 Pro, **iOS 26.0.1**, with Xcode 26.0.1. The acceptance app uses the separate identifier `com.vava.h5acceptance.rn54027e83`; its embedded React Native bundle starts the local H5 pages without Metro. The original `im.seex.sao2` installation was not replaced.

- Both TypeScript checks passed. The static verifier passed **609 source and resource checks**, including archive/source freshness. `git diff --check` passed.
- The hosted integration test passed **1 test, 0 failures, 0 skips**, in 21.748 seconds. It retained **20 screenshots**. The actual document URL was a local `index.html`.
- Verified agreement-gated entry; all five tabs; course, publisher, replay, source and credits pages; the restricted publisher conversation; nearby discovery; private comments; video readiness and vertical swipe changes; import form; wallet; settings; blocked publishers; saved lesson/replay state; and persisted profile editing.
- The H5 wallet purchased **400 coins** using StoreKit Test. Cancellation preserved the exact ledger bytes. Replaying the same verified transaction **12 times** left the balance at 400 and the ledger at one entry. Returning to Me showed the updated balance. Logging out, logging in and reloading the document restored the same account and balance.
- A subsequent process cold launch opened Academy successfully from the installed local archive. The isolated persisted wallet remained at **400 coins / 1 entry**. The original app's library and wallet JSON file set and SHA-256 hashes matched the pre-migration baseline exactly.
- The archive inside the built app exactly matched `Assets/LocalWeb/vava.zip`: SHA-256 `319f2a343eb742bd932660b8452fdb8189ed0d34989b522956bebe17a7b0d411`.

Evidence: `/tmp/vava-h5-final.xcresult`, `/tmp/vava-h5-final.log`, `/tmp/vava-h5-final-summary.json`, `/tmp/vava-h5-final-images`, and `/tmp/vava-h5-cold-start.png`. The isolated app is left running on Academy for inspection. Earlier failed iterations exposed a Fabric legacy view-registry lookup issue; the final acknowledged property transport passed the same regression path. Browser touch coordinates and modal keyboard height also received explicit web adaptations.

The runtime test drives real DOM handlers and native commands inside WKWebView; it is not a physical touch/VoiceOver sweep. Source and agreement browser sheets, actual Photos imports, all reporting/blocking combinations, pending purchases, purchase-verification/storage failures and larger accessibility text sizes were not exhaustively rerun in this migration. Discovery and the restricted conversation UI passed, but reciprocal nearby messaging and connected voice/video calls require two physical iPhones. Apple sandbox, production purchases and Release/device signing remain unverified. The desktop simulator-control connection timed out; screenshots and hosted WKWebView checks supplied the executed evidence.

## Branding update on November 17, 2026

The owner-provided Vava logo now supplies the launcher icon and the local H5 welcome/login, loading and error branding. Native shell loading/error views use the same asset. See [artwork provenance](Media.md#current-vava-logo). The owner authorized H5 packaging only for this update: `npm run build:web` succeeded, 611 static source/resource checks passed, and image verification confirmed unchanged launcher pixels and identical supplied PNG bytes in the H5 archive. The updated archive SHA-256 is `fafd0ab130e769ec17adc7affdf91b262629bd50f3cc0fb52f18af5aad2f6540`.

No iOS build, typecheck, installation, simulator launch or runtime test was performed for this branding update. The November 16 runtime evidence above predates the new logo and is not acceptance evidence for its rendered layout. The existing UI test entry selector now locates the accessible logo instead of the replaced text wordmark; that selector has not been rerun.

## Pull-to-refresh and publisher actions on November 17, 2026

Repackaged the local H5 archive and passed 611 static checks. The `Vava` Debug scheme built from `Vava.xcworkspace` with Xcode 26.0.1. The build produced `ZIPFoundation.modulemap` and embedded the exact regenerated H5 archive.

Installed the new Debug build on **Vava UI Acceptance**, iPhone 17 Pro, **iOS 26.0.1**. An XCUITest sent simulator touch drags and observed `Updated` on Academy, Watch, Chats, Me, and Wallet. Each screen had no standalone Refresh button. On the publisher profile, the test measured equal Follow and Message dimensions, aligned the Block icon with both buttons, and opened and canceled the block confirmation. The test passed with 1 test, 0 failures, and 0 skips. The two existing application-support JSON files retained their SHA-256 digests.

Evidence: `/tmp/vava-workspace-build.wdkEU1/WorkspaceBuild.xcresult` and `/tmp/vava-touch-acceptance.iNN0lq/DeviceResults.xcresult`. This run covered the publisher profile and the five listed refresh routes. Nearby player discovery and StoreKit purchases were outside its scope.

A follow-up Shorts XCUITest on the same simulator passed with 1 test, 0 failures, and 0 skips. A downward drag on the first clip displayed `Shorts updated` and advanced to the second clip. An upward drag advanced to the third clip, two downward drags returned to the first clip, and an upward drag from the first clip advanced to the second. Evidence: `/tmp/vava-shorts-acceptance.LCGp33/ShortsResults.xcresult`.

## StoreKit 1 repair on November 17, 2026

The active wallet now uses StoreKit 1 as requested by the owner. Earlier StoreKit 2 purchase evidence above remains historical. See [the diagnosis, receipt verification boundary and new acceptance record](StoreKit1Repair.md). The presentation remains local H5 through the React Native shell.
