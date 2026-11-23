# Integration status

## Application framework

The Swift application delegate displays the UIKit login screen and opens a tab controller with five navigation stacks. The controllers call the existing library, wallet, media and nearby services directly.

## On-device library

Vava uses the bundled Assets catalog and local profile, consent, activity, notes, course progress, imported videos, and wallet. First launch records acceptance under revision `2026-11-13.2`. The owner changed the reading links. The consent revision is retained. Debug uses Bundle ID `im.seex.sao2` with Yu Sun (`JPTS6M4T5B`). Release uses `com.vava.pingpong`. Each Bundle ID has its own app container. The on-device library preserves the profile identifier from a previous session file when present, then removes that session file.

Short clips, photos, replay covers, and fonts are included in the app. Publisher replay, coaching, source, license, and agreement links need internet access. The app has no online authentication, message relay, or cloud moderation. Imported Photos originals remain outside the app's copy and removal workflow.

## Account access

Cold launch and sign-out both show the login screen. Both require a checked agreement box and an explicit Log in action. The login controller validates the selection and writes consent when the revision changes. The existing profile and account-specific wallet are restored on login.

Account deletion records the request before clearing the profile, both wallet ledgers, and imported video copies. An interrupted deletion resumes before sign-in. A new profile gets a new account ID and accepts the current agreements.

## StoreKit coin packs

`Configuration/coin-products.json` defines the wallet catalog for `com.vava.pingpong`. The seven owner-supplied mappings are joined by two new consumables. The new quantities keep coins per dollar between the surrounding tiers.

| Reference USD | Coins | Product ID | Source |
| ---: | ---: | --- | --- |
| 0.99 | 400 | `ampqtftkneoumheh` | Owner catalog |
| 1.99 | 800 | `xtvhwdsgjloktbwl` | Owner catalog |
| 4.99 | 2,450 | `ofodmhntljhmyqmu` | Owner catalog |
| 9.99 | 5,150 | `kngnkmkillhkjekc` | Owner catalog |
| 19.99 | 10,800 | `wmiafabmsrgzdnfy` | Owner catalog |
| 29.99 | 16,800 | `oeryktujrjycpirn` | New |
| 49.99 | 29,400 | `abnkqxwpzttscctn` | Owner catalog |
| 69.99 | 42,600 | `tocftlpnavpjddox` | New |
| 99.99 | 63,700 | `bxmlhefhtmbillwb` | Owner catalog |

The wallet uses StoreKit 1 (`SKProductsRequest`, `SKProduct`, `SKMutablePayment`, and `SKPaymentQueue`) as requested by the owner on November 17. It enables checkout only for returned catalog products and formats their prices with the returned `priceLocale`. Reference USD values configure the catalogs; they are not fallback display prices. Payment carries the local profile UUID in `applicationUsername`. Delivery validates the local signed app receipt, transaction identifier, product, quantity, bundle, environment and cancellation status before atomically crediting the matching local account and finishing the queue transaction. Legacy receipts do not supply a signed account token; ownership also requires the matching queue payment username. A missing or mismatched username is not reassigned to the current account. Pending or canceled purchases leave the balance unchanged. Wallet balances and course unlocks stay on the device.

The shared `Vava` scheme uses `Configuration/VavaCoins.storekit` for Debug Run. Open `Vava.xcodeproj`. Xcode resolves the scheme reference from its internal `Vava.xcodeproj/project.xcworkspace`. The `../../` prefix in `project.yml` reaches the app directory and selects the checked-in fixture. Run from Xcode to load the nine local offers. The `VAVA_LOCAL_STOREKIT` Run variable selects a separate per-profile ledger that accepts verified `.xcode` transactions. The fixture stays outside the app bundle. Choosing a local ledger with an environment variable does not activate a StoreKit catalog; launch from the configured Xcode Run action, or initialize SKTestSession in an isolated test runner. A plain CLI or Home Screen launch does not establish fixture activation. Release uses the existing Apple ledger and accepts verified `.sandbox` and `.production` transactions.

Debug simulator launches default to the local StoreKit ledger even when opened from the Home Screen without Xcode's environment variables. Set `VAVA_LOCAL_STOREKIT=0` explicitly when testing the Apple catalog on a Debug simulator. Debug physical-device builds require `VAVA_LOCAL_STOREKIT=1` for local StoreKit. Unfinished transactions are retried on launch and credited once after verification.

Delivery failures are tracked per transaction in the current wallet session, logged without receipt contents, and exposed to Me and Wallet through wallet change notifications. Startup rebuilds failure state by checking unfinished transactions. Wallet offers an explicit Retry purchases action and retries unfinished delivery when opened or refreshed. A failed attempt leaves the balance and transaction unfinished; verification and atomic saving must succeed before finishing. Background feedback is scoped to the current profile and StoreKit environment. Unverified payload fields are used only to scope feedback, never to authorize credit.

To check the Apple sandbox for `com.vava.pingpong`, use a Release-signed build for that Bundle ID with StoreKit Configuration set to None. Reconcile the seven supplied IDs in App Store Connect for `com.vava.pingpong` and create the two new IDs as consumables with the listed prices. Confirm signing, product metadata, pricing and availability, then verify catalog loading and purchase delivery using a Sandbox Apple Account. Use the `InAppPurchase` log category to distinguish missing products from a StoreKit request error. Empty catalogs reject refresh rather than displaying Updated. Partial catalogs retain usable offers and show an availability notice. Product requests have retained delegates, cancellation and a 20-second timeout. See [StoreKit 1 repair and evidence](StoreKit1Repair.md). See [Apple's consumable setup](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases) and [sandbox catalog troubleshooting](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox).

Local follow-up acceptance on November 16, 2026 verified successful purchases, cancellation, duplicate verified callbacks and cold-restart persistence in an isolated React Native application on Vava UI Acceptance. The original wallet and library remained byte-for-byte unchanged. See [local StoreKit evidence and limits](WalletStoreKitAcceptance.md).

## Shorts activity

Bundled clips have stable publisher IDs and labeled estimates for likes, saves, and shares. The per-clip display adds locally saved likes, bookmarks, and completed system share actions to those estimates. Profile totals and work cards use that same calculation. Imported works start with zero activity and contribute only their own local interactions to the Me profile. Legacy local-library snapshots decode missing follow, block, and share fields as empty.

The Shorts rail and the comments sheet use the same count of bundled editorial notes plus private comments and replies on this device. Vava Editorial wrote the notes after reviewing representative footage. The sheet shows selected notes first and displays a date and time for private comments and replies with a recorded save time. The catalog contains 26 notes for Ravne league final, 30 for Netherlands vs China, 22 for A game between brothers, and 24 for Table tennis outdoors. Editorial IDs are stable so private replies keep their references. Imported videos have no editorial notes.

## Coaching sources and content controls

Each lesson credits a public coaching source. Its list entry, detail, and source profile share the same name and photo. The Academy practice plans are Vava content linked to these public references. See [photo provenance](../Assets/Content/publisher-photo-sources.json) for the portrait sources and the licensed England team photo.

Reporting a catalog clip or lesson stores the selected reason and timestamp in the protected app container and hides that item in the same write. The app keeps these reports as personal records. Review is unavailable. Blocking removes the publisher's works from discovery, search, and personal collections while preserving saved items and course access. Unblock from Settings to restore eligible works.

## Nearby chat and calls

Chat discovery uses an encrypted Multipeer Connectivity session. Open Find players on two nearby iPhones, allow network access, confirm the other player's code and follow each other. Each installation proves possession of a stable signing key stored with its protected profile. Both peers enforce mutual follows and blocks before accepting a message or a call. A message becomes confirmed only after the receiving device saves it and acknowledges its identifier. Unconfirmed messages can be retried with the same identifier. No relay, background call delivery, or cross-device history sync is configured.

A denied conversation creates a private notice in its owner's history. Editorial publisher identities cannot receive messages or calls. Earlier email contacts and drafts remain in the account snapshot for compatibility and are excluded from message history.

Inbox controls save with the conversation. Opening a thread clears its unread marker. Deleting a row clears its pin and unread marker and hides it until there is new activity. Message history and the other player's inbox remain intact.

Calls signal through the same connection. Audio uses AVAudioEngine voice processing. Video sends bounded front-camera frames only during the accepted call. Microphone or camera denial, loss of connection, and leaving the app end the call. Use two physical iPhones for message and call acceptance.

The Call preview route remains available for internal media checks, with no inbox entry. Voice preview checks microphone authorization. Video preview also requests camera authorization and displays local front-camera frames on a supported device. Preview frames stay on the device. Leaving the preview or putting Vava in the background stops capture. Run the camera preview on a physical iPhone to verify live frames.

Profile photos selected through Photos are stored as compact JPEGs with the profile. Owned videos display that photo. Catalog clips share their source image with the publisher profile.

## Agreement links

Welcome and Settings open the owner-provided [Terms of Service](https://docs.google.com/document/d/1HKDBNvyA7Vha5_sVVoc4P4Z8e-udZkrMlfdbTgVvdOs) and [Privacy Policy](https://docs.google.com/document/d/1_ldTUi2Y1bfT5x9BphLfDo3AwM7ZBpNxUnHFmwI2GFo) in the system browser sheet. Verified both document pages and PDF exports with anonymous HTTPS requests after the owner enabled link sharing. Both returned HTTP 200, and the exported PDFs contained readable text. The previous editable sources and PDF drafts are archived under `Assets`.

## Retired project

The 139 Supabase project `buraihehitvpbbtuktye` is no longer referenced by the runtime. The previous session filename is recognized only for on-device account-ID compatibility. The live inventory contained no accounts, messages, or Storage objects. All 16 catalog entries and six course exercise sets matched the local source before cutover. Historical migration SQL and seed files are retained for provenance.

Project deletion remains pending. The connector lacks a project deletion operation, and the browser session only had access to the Gmail organization. The deletion target is [Table Tennis iOS](https://supabase.com/dashboard/project/buraihehitvpbbtuktye/settings/general) under the 139 organization.
