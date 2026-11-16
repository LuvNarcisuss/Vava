# Integration status

## On-device library

Vava uses the bundled Assets catalog and local profile, consent, activity, notes, course progress, imported videos, and wallet. First launch records acceptance under revision `2026-11-13.2`. The owner changed the reading links. The consent revision is retained. Debug uses Bundle ID `im.seex.sao2` with Yu Sun (`JPTS6M4T5B`). Release uses `com.vava.pingpong`. Each Bundle ID has its own app container. The on-device library preserves the profile identifier from a previous session file when present, then removes that session file.

Short clips, photos, replay covers, and fonts are included in the app. Publisher replay, coaching, source, license, and agreement links need internet access. The app has no connected authentication, messaging, or cloud moderation. Imported Photos originals remain outside the app's copy and removal workflow.

## Account access

Logging out preserves the profile and its wallet. The saved sign-out state requires an explicit Log in action on the welcome screen. The current consent revision remains valid for that profile.

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

The wallet enables checkout only for consumables returned by StoreKit and displays their localized `displayPrice`. The reference USD values are for configuring the catalogs. The wallet passes the local profile UUID as the app account token. It credits a verified transaction to the matching profile once, saves the ledger atomically, and then finishes the transaction. Pending or canceled purchases leave the balance unchanged. Wallet balances and course unlocks stay on the device.

The shared `Vava` scheme uses `Configuration/VavaCoins.storekit` for Debug Run. Run from Xcode to load the nine local offers. The `VAVA_LOCAL_STOREKIT` Run variable selects a separate per-profile ledger that accepts verified `.xcode` transactions. The fixture stays outside the app bundle. Release uses the existing Apple ledger and accepts verified `.sandbox` and `.production` transactions.

Debug simulator launches default to the local StoreKit ledger even when opened from the Home Screen without Xcode's environment variables. Set `VAVA_LOCAL_STOREKIT=0` explicitly when testing the Apple catalog on a Debug simulator. Debug physical-device builds require `VAVA_LOCAL_STOREKIT=1` for local StoreKit. Unfinished transactions are retried on launch and credited once after verification.

Delivery failures are tracked per transaction in the current wallet session, logged without receipt contents, and exposed to Me and Wallet through wallet change notifications. Startup rebuilds failure state by checking unfinished transactions. Wallet offers an explicit Retry purchases action and retries unfinished delivery when opened or refreshed. A failed attempt leaves the balance and transaction unfinished; verification and atomic saving must succeed before finishing. Background feedback is scoped to the current profile and StoreKit environment. Unverified payload fields are used only to scope feedback, never to authorize credit.

To check the Apple sandbox for `com.vava.pingpong`, use a Release-signed build for that Bundle ID with StoreKit Configuration set to None. Reconcile the seven supplied IDs in App Store Connect for `com.vava.pingpong` and create the two new IDs as consumables with the listed prices. Confirm signing, product metadata, pricing and availability, then verify catalog loading and purchase delivery using a Sandbox Apple Account. Use the `InAppPurchase` log category to distinguish missing consumables from a StoreKit request error. See [Apple's consumable setup](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases) and [sandbox catalog troubleshooting](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox).

## Shorts activity

Bundled clips have stable publisher IDs and labeled estimates for likes, saves, and shares. The per-clip display adds locally saved likes, bookmarks, and completed system share actions to those estimates. Profile totals and work cards use that same calculation. Imported works start with zero activity and contribute only their own local interactions to the Me profile. Legacy local-library snapshots decode missing follow, block, and share fields as empty.

The Shorts rail and the comments sheet use the same count of bundled editorial notes plus private comments and replies on this device. Vava Editorial wrote the notes after reviewing representative footage. The sheet shows selected notes first and displays a date and time for private comments and replies with a recorded save time. The catalog contains 26 notes for Ravne league final, 30 for Netherlands vs China, 22 for A game between brothers, and 24 for Table tennis outdoors. Editorial IDs are stable so private replies keep their references. Imported videos have no editorial notes.

## Coaching sources and content controls

Each lesson credits a public coaching source. Its list entry, detail, and source profile share the same name and photo. The Academy practice plans are Vava content linked to these public references. See [photo provenance](../Assets/Content/publisher-photo-sources.json) for the portrait sources and the licensed England team photo.

Reporting a catalog clip or lesson stores the selected reason and timestamp in the protected app container and hides that item in the same write. The app keeps these reports as personal records. Review is unavailable. Blocking removes the publisher's works from discovery, search, and personal collections while preserving saved items and course access. Unblock from Settings to restore eligible works.

## Contacts and drafts

Chats uses the contacts saved by the current profile. Contact conversations retain drafts and open a Mail compose link when the user chooses to continue. Publisher drafts can be reopened from Chats and remain private. The app does not record external delivery. Blocking a publisher hides their drafts and works until unblocked.

Profile photos selected through Photos are stored as compact JPEGs with the profile. Owned videos display that photo. Catalog clips share their source image with the publisher profile.

## Agreement links

Welcome and Settings open the owner-provided [Terms of Service](https://docs.google.com/document/d/1HKDBNvyA7Vha5_sVVoc4P4Z8e-udZkrMlfdbTgVvdOs) and [Privacy Policy](https://docs.google.com/document/d/1_ldTUi2Y1bfT5x9BphLfDo3AwM7ZBpNxUnHFmwI2GFo) in the system browser sheet. Verified both document pages and PDF exports with anonymous HTTPS requests after the owner enabled link sharing. Both returned HTTP 200, and the exported PDFs contained readable text. The previous editable sources and PDF drafts are archived under `Assets`.

## Retired project

The 139 Supabase project `buraihehitvpbbtuktye` is no longer referenced by the runtime. The previous session filename is recognized only for on-device account-ID compatibility. The live inventory contained no accounts, messages, or Storage objects. All 16 catalog entries and six course exercise sets matched the local source before cutover. Historical migration SQL and seed files are retained for provenance.

Project deletion remains pending. The connector lacks a project deletion operation, and the browser session only had access to the Gmail organization. The deletion target is [Table Tennis iOS](https://supabase.com/dashboard/project/buraihehitvpbbtuktye/settings/general) under the 139 organization.
