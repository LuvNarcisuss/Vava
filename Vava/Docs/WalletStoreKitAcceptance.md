# Local StoreKit wallet acceptance

Date: November 16, 2026. The owner authorized successful local purchases, cancellation and duplicate-delivery verification while preserving the original wallet.

## Environment and isolation

- Simulator: Vava UI Acceptance, iPhone 17 Pro, UUID `C6BBDAF1-EF03-4F2E-980F-CB8C472367D6`.
- Actual runtime: iOS 26.0.1, confirmed by `simctl getenv ... SIMULATOR_RUNTIME_VERSION` and the XCTest result. Simulator's window label abbreviates this to iOS 26.0.
- Tools: Xcode 26.0.1; the current React Native workspace and native Wallet source.
- Test application: `com.vava.walletacceptance.rn4a85232b`, displayed as Vava Wallet Test.
- Original application: `im.seex.sao2`. It was paused during test purchases and restored afterward. No test purchase was made in its container.
- Original data baseline: `/tmp/vava-wallet-owner-baseline-20261116`. Both original JSON files were backed up, and their file set and SHA-256 hashes were compared after restoring the original application. All bytes remained unchanged.

## Observed results

| Check | Result |
| --- | --- |
| Native purchase success | The production `Wallet.buy` method completed a StoreKit Test purchase of 400 coins. The ledger moved from 0 to 400 and contained one transaction entry. The verified result had the Xcode environment and matching account token. |
| Native cancellation | StoreKit Test injected user cancellation into the purchase API. The method returned Purchase canceled, with the balance, entry count and persisted ledger bytes unchanged. |
| Duplicate callbacks | The exact StoreKit-verified result for transaction 17 was submitted to the production `receive` handler 12 times using a task group. Balance remained 400, entry count remained one, no delivery issue appeared, and ledger bytes remained identical. |
| Duplicate after ledger reopen | The first Wallet instance was stopped, a new instance loaded the same persisted account ledger, and the same verified transaction was submitted again. Balance remained 400 with one entry and unchanged bytes. Pending-transaction scans also preserved it. |
| React Native success | In the isolated app's Wallet screen, an 800-coin purchase was confirmed in the Xcode test sheet, which explicitly stated no charge. The app displayed Coins added to your wallet, balance 1,200, and one new +800 entry alongside the prior +400 entry. The persisted ledger contained exactly two unique transaction IDs. |
| React Native cancellation | A second 800-coin checkout was canceled in the native test sheet. The app displayed Purchase canceled. Persisted ledger bytes exactly matched the state after the successful purchase. |
| Process cold restart | The isolated app was terminated and relaunched. Me and Wallet both displayed 1,200; Wallet showed exactly the +800 and +400 entries. Persisted bytes remained unchanged. |
| Original data | The original library and wallet file set and byte hashes matched the pre-test baseline after the original app was relaunched. No restore or rewrite of original data was necessary. |

## Changes and verification evidence

No wallet crediting or cancellation defect was found. The production transaction receiver changed from private to module-internal visibility so an `@testable` integration test can replay an authentic verified callback through the same validation and persistence path used by live updates. No new JavaScript command, credit bypass or transaction fabrication was added.

Added `Tests/WalletStoreKitTests.swift` and `Tests/prepare_wallet_acceptance.rb`. The latter generates a fresh isolated application and test target with the current workspace dependencies. The test harness supplies its own Info.plist and finished-consumable history setting; the production Info.plist and identities are unchanged. Apple's [finished-consumable history documentation](https://developer.apple.com/documentation/BundleResources/Information-Property-List/SKIncludeConsumableInAppPurchaseHistory) explains why that setting is needed to retrieve a completed transaction for replay.

The first harness build exposed missing test-target linker configuration; the helper now supplies libc++ without relinking the host's entire pod graph. The first executable attempt passed the success assertions but could not retrieve a finished consumable under the default history setting. A fresh isolated run with the corrected test-only configuration passed the complete test. These were harness issues, not payment failures.

Final XCTest result: one integration test passed, zero failures, zero skips. Test execution took 1.251 seconds after the build and launch. The result bundle confirms the designated simulator UUID. Static verification passed 572 assertions, Ruby syntax checking passed, and `git diff --check` passed.

- Result bundle: `/tmp/vava-wallet-storekit-20261116-retry2.xcresult`.
- Build and test log: `/tmp/vava-wallet-storekit-20261116-retry2.log`.
- Isolated harness metadata: `/var/folders/pz/ttf8016n5n7gnbqtdwfdjl7m0000gn/T/vava-wallet-rn-20261116-48609-aiutwz/acceptance.json`.
- Ledger baseline after manual success: `/tmp/vava-wallet-ui-success.json`.

Temporary artifacts may be removed by system cleanup. Reproduction instructions are in [Tests/README.md](../Tests/README.md).

## Boundary

These results cover local Xcode StoreKit Test on the specified simulator, including the real native purchase API and migrated React Native UI. The repeated callback check is deterministic replay of one authentic verified result into the production handler; it is not a claim that Apple's server emitted 12 duplicate notifications. No Apple sandbox or production transaction, real charge, deferred approval, verification failure or storage-failure scenario was exercised in this run. The historical broader UIKit feedback suite still needs adaptation for the React Native accessibility tree.
