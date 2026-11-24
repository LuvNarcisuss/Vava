# Vava

Open `Vava.xcodeproj` and select the Vava scheme with the `Vava QA` iPhone 17 Pro run destination. Xcode resolves the locked Swift packages for receipt validation. The application uses Swift and UIKit on iPhone with iOS 16 or later.

## Project layout

- `App/Core` contains the UIKit application entry, theme and shared Swift services.
- `App/Features` contains the native screens for Academy, Watch, Shorts, Chats, Me and their detail flows.
- `Assets` holds the bundled catalog, media, art, fonts, agreements and editable sources.
- `Backend/account_auth.sql` defines the company Supabase account schema.
- `supabase` archives the retired backend's migrations and catalog seed.
- `Docs` records scope, deployment status and static verification.

## Configure for distribution

Vava is the app display name in `App/Info.plist`. Debug and Release use `com.vava.pinghjsd`. Debug Run uses the local StoreKit catalog. Signing settings are in `project.yml`. See [StoreKit coin packs](Docs/Integration.md#storekit-coin-packs) for Apple sandbox setup. Regenerate project metadata with `xcodegen generate` after changing project settings.

See [Integration status](Docs/Integration.md) for company account configuration, local data ownership, and the retired backend. See [Media credits](Docs/Media.md) for sources and rights.
