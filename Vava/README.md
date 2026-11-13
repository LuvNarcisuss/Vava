# Vava

Open `Vava.xcodeproj` and select the Vava scheme. The table tennis app uses Swift 5, UIKit and iOS 16 or later.

## Project layout

- `App/Core` holds the theme, navigation, local library and wallet.
- `App/Features` holds Shorts, Academy, Watch, Chats and Me.
- `Assets` holds the bundled catalog, media, art, fonts, agreements and editable sources.
- `supabase` archives the retired backend's migrations and catalog seed.
- `Docs` records scope, deployment status and static verification.

## Configure for distribution

Vava is the app display name in `App/Info.plist`. The Bundle ID is `com.vava.pingpong`. Set the signing team in `project.yml` when provided. Enter the owner-confirmed Apple consumable IDs in `Configuration/coin-products.json`. StoreKit supplies the localized prices. Regenerate project metadata with `xcodegen generate` after changing project settings.

See [Integration status](Docs/Integration.md) for the local data scope and retirement status. See [Media credits](Docs/Media.md) for sources and rights.
