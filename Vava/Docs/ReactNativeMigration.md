# React Native migration

Current presentation: all product pages now render as local H5 inside a React Native initialized WKWebView. See [local H5 architecture and current acceptance](LocalH5Migration.md). Earlier React Native runtime evidence below describes the preceding renderer and does not establish H5 acceptance.

## Architecture

Vava uses React Native and TypeScript for product screens and navigation. The existing iOS application hosts the `Vava` JavaScript component through `RCTReactNativeFactory`. The selected integration uses the existing Xcode project and CocoaPods. React Native is pinned to 0.85.3 and React to 19.2.3. The project targets iPhone with iOS 16 or later.

`ReactNative/native.ts` defines the snapshot and asynchronous command interface. `VavaNative` owns account access, the catalog, protected local storage, StoreKit transactions and nearby chat. React renders saved state and invokes native operations. Monotonic snapshot revisions prevent older asynchronous responses from replacing newer state. `VavaVideo` owns AVPlayer playback and `VavaCallVideo` receives video frames from the existing call service. System Photos, share and browser sheets are native platform interfaces.

The native service keeps the existing protected library, imported media and account-specific wallet locations. The migration reuses serialized identifiers, consent revision, product IDs and transaction delivery logic. Existing private data requires no export or replacement.

The preceding UIKit interface is retained in `App/Features`, `App/Core/Theme.swift`, and `Legacy/VavaApplication.swift` for migration traceability. These files are excluded from the application target. New product interfaces belong in `ReactNative`.

## Dependency and project setup

Use the Node version accepted by package.json. Run `npm ci` to install the locked JavaScript dependencies. Generate metadata with `xcodegen generate`, then run `pod install` from this directory and open `Vava.xcworkspace`. Repeat CocoaPods integration after regenerating the project.

Debug loads JavaScript from Metro. Once execution is authorized, `npm start` starts Metro. The Xcode release build phase embeds the JavaScript bundle and referenced assets. `.xcode.env` resolves Node from the build environment. Configure a machine-local `.xcode.env.local` when Xcode requires an explicit Node executable.

Debug retains `im.seex.sao2` with the existing local StoreKit configuration. Release retains `com.vava.pingpong`. Both configurations retain the Vava target, Vava shared scheme and Yu Sun development team.

## Verification

On November 16, 2026, the owner authorized compilation, launch and functional checks on the designated simulator. `npm run typecheck` passed, the static verifier passed 572 assertions, and the Debug workspace built with Xcode 26.0.1. The current application was installed and launched on Vava UI Acceptance, iPhone 17 Pro, iOS 26.0, using the existing Debug app container. Primary routes and reversible state changes were checked through the simulator UI. See [the acceptance record](ReactNativeAcceptance.md) for exact coverage and limitations.

The run fixed missing React Native TypeScript ambient types, native view initializer errors, the C++ linker dependency, status bar configuration, deprecated safe-area rendering, and swipe handling when touch movement is coalesced. Safe-area rendering uses the locked `react-native-safe-area-context` dependency. The final cold-start console contains no application warning or exception.

The follow-up [local StoreKit acceptance](WalletStoreKitAcceptance.md) verified successful native and React Native purchases, cancellation, 12 duplicate verified callbacks, an additional duplicate after reopening the wallet, and persistence across process restart in an isolated application. The original wallet and library bytes remained unchanged. Deferred purchases and verification/storage failures were not rerun. Apple sandbox and production readiness remain unverified. Nearby message delivery and calls require two physical iPhones and remain pending.

The integration follows the [React Native existing-app guide](https://reactnative.dev/docs/integration-with-existing-apps) and the [0.85 community template](https://github.com/react-native-community/template/tree/0.85-stable/template).
