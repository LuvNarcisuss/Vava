# Wallet launch-mode regression

November 16, 2026, Asia/Shanghai

## Cause and change

The Debug scheme supplied `VAVA_LOCAL_STOREKIT=1`, but launches without that variable selected the Apple ledger and rejected verified Xcode transactions. This could show an empty wallet or reject a completed local purchase.

Debug simulator builds now select the isolated local StoreKit ledger by default. Explicit `VAVA_LOCAL_STOREKIT=0` selects the Apple ledger. Debug physical-device and Release policies are unchanged. Existing balances, profile identifiers, verification, transaction deduplication, atomic persistence, and finish-after-credit behavior are preserved.

## Observed validation

Environment: Xcode 26.0.1, Vava UI Acceptance, iPhone 17 Pro, iOS 26.0.1, simulator `C6BBDAF1-EF03-4F2E-980F-CB8C472367D6`.

The isolated UI fixture used the current workspace App sources and `com.vava.pingpong.acceptance.nov13`. Its data was reset between independent purchase cases; the user's `im.seex.sao2` container was not reset.

- Before the change, an 800-coin local purchase with an empty launch variable failed with "This transaction could not be credited to your wallet." The success assertion failed.
- After updating the same test installation, the unfinished transaction recovered automatically. The balance was 800 with one purchase entry. Relaunching with the Xcode variable set to `1` preserved the same balance and entry.
- A fresh installation completed an 800-coin purchase with an empty launch variable. Restart preserved 800 coins and exactly one purchase entry.
- The existing wallet regression passed: all nine offers loaded, native cancellation created no entry, pending and declined purchases left the wallet empty, a verified purchase added 400 coins, and a course unlock spent 45. Restart retained 355 coins and one purchase entry.
- Workspace Debug and Release simulator builds succeeded. The static verifier passed 536 checks, and strict Swift format lint passed for `Wallet.swift`.
- The latest workspace Debug build was installed over `im.seex.sao2` without resetting its container and launched without the Xcode environment variable. Its original profile automatically recovered an unfinished purchase: the local ledger changed from absent to a balance of 800 with exactly one `Coin pack` entry for +800 and a StoreKit transaction identifier. No new purchase was initiated in that app during this validation. The app reached Academy.

Result bundles are in `/tmp/vava-acceptance.0z0B6Y`: `wallet-env-red.xcresult`, `wallet-recovery-green.xcresult`, `wallet-new-green.xcresult`, and `wallet-standard-green.xcresult`. The red case is the expected pre-fix failure. Three post-fix UI tests passed with zero failures.

## Limits

These were local StoreKit Test transactions, not Apple sandbox or production purchases. The original profile's recovered balance was confirmed by reading its persisted ledger. Existing compiler warnings about actor isolation, AVAssetExportSession sendability, and deprecated button insets remain outside this change.
