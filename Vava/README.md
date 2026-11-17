# Vava

Install the dependencies using `npm ci`, package the local H5 pages with `npm run build:web`, generate the project with `xcodegen generate`, and integrate native dependencies with `pod install`. Open `Vava.xcworkspace` and select the Vava scheme. Vava uses a React Native shell displaying bundled local H5 pages, with Swift platform modules on iPhone, iOS 16 or later. See [migration setup and verification](Docs/ReactNativeMigration.md).

## Project layout

- `ReactNative` holds the native shell, shared presentation source and typed native interface.
- `Web` holds H5 entry, browser adapters and styles; `Assets/LocalWeb/vava.zip` is its packaged output. See [local H5 migration](Docs/LocalH5Migration.md).
- `App/Core` holds the iOS host, local library, wallet and nearby communication.
- `App/ReactNative` holds the native service and media bridges.
- `App/Features`, `App/Core/Theme.swift` and `Legacy` retain the previous UIKit interface outside the target.
- `Assets` holds the bundled catalog, media, art, fonts, agreements and editable sources.
- `supabase` archives the retired backend's migrations and catalog seed.
- `Docs` records scope, deployment status and static verification.

## Configure for distribution

Vava is the app display name in `App/Info.plist`. Release uses `com.vava.pingpong`. Debug Run uses `im.seex.sao2`, the Yu Sun team, and the local StoreKit catalog. Signing settings are in `project.yml`. See [StoreKit coin packs](Docs/Integration.md#storekit-coin-packs) for Apple sandbox setup. Regenerate project metadata with `xcodegen generate` after changing project settings, then run `pod install` to restore native dependency integration.

See [Integration status](Docs/Integration.md) for the local data scope and retirement status. See [Media credits](Docs/Media.md) for sources and rights.
