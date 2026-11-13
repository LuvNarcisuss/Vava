# Integration status

## On-device library

Vava uses the bundled Assets catalog and local profile, consent, activity, notes, course progress, imported videos, and wallet. The first launch accepts the bundled agreement revision `2026-11-13.2`. The app uses Bundle ID `com.vava.pingpong`. The on-device library preserves the profile identifier from a previous session file when present, then removes that session file. StoreKit still requires the owner's product identifiers and Apple signing configuration.

Short clips, photos, replay covers, fonts, and the two PDFs are included in the app. Publisher replay, coaching, source, and license links need internet access. Connected authentication, private messaging and cloud moderation are unavailable. Imported Photos originals remain outside the app's copy and removal workflow.

## Retired project

The 139 Supabase project `buraihehitvpbbtuktye` is no longer referenced by the runtime. The previous session filename is recognized only for on-device account-ID compatibility. The live inventory contained no accounts, messages, or Storage objects. All 16 catalog entries and six course exercise sets matched the local source before cutover. Historical migration SQL and seed files are retained for provenance.

Project deletion remains pending. The connector lacks a project deletion operation, and the browser session only had access to the Gmail organization. The deletion target is [Table Tennis iOS](https://supabase.com/dashboard/project/buraihehitvpbbtuktye/settings/general) under the 139 organization.
