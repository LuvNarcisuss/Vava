# Current StoreKit 1 verification

The isolated harness also includes `ContentVisibilityTests`. It checks loaded-screen updates, report/block independence in both undo orders, blocked chat filtering without history deletion, separate accounts, rejected targets, direct hidden detail/comment routes, failed writes and retries, and durable local audit history. See [current safety acceptance](../Docs/Acceptance/2026-11-23-safety/report.md) for executed results.

For gesture and navigation acceptance, run `ruby Tests/prepare_safety_acceptance.rb` with the `xcodeproj` gem available. It creates a separate application identifier, copies the current App sources, and substitutes only the copied app entry point with `SafetyTestHost.swift`. The fixture opens isolated local account data without claiming a successful network login. It seeds saved items and an editorial chat record only in that isolated account. The production target does not include the fixture or UI tests. `--fail-safety-writes` replaces only the isolated account's library file path with a nonempty directory to exercise actual write failures.

Use the returned project with scheme `VavaSafetyAcceptance`, the returned Vava QA destination, and `-parallel-testing-enabled NO test`. `SafetyUITests.swift` uses the production screens and normal buttons, long presses, confirmation dialogs and tab navigation. Each test uses a unique account; the restart case reuses its account without reseeding. No live authentication, remote moderation or purchases are exercised by this harness.

The active tests now use SKProductsRequest and SKPaymentQueue through the production wallet. A test-only observer captures real purchased queue transactions for duplicate callback replay; tests no longer use StoreKit 2 Transaction.latest or VerificationResult. The isolated wallet suite includes an empty-catalog rejection and recovery regression. Local receipts are validated before credit. See [current repair evidence](../Docs/StoreKit1Repair.md). The older runtime outcomes below predate this migration unless explicitly dated otherwise.

# Wallet acceptance tests

## Native wallet coverage

`WalletStoreKitTests.swift` runs against the production Wallet implementation inside an isolated build of the Swift application. It verifies a successful 400-coin purchase, cancellation with identical persisted bytes, 12 repeated callbacks carrying the same StoreKit-verified transaction, and another duplicate after reopening the wallet. A hosted interface test opens an isolated local profile and uses the profile and wallet controls, checks the nine prices, and verifies the result messages, activity and updated profile balance. StoreKit Test supplies the transactions. See [the current verification record](../Docs/Verification.md) and [the earlier acceptance record](../Docs/WalletStoreKitAcceptance.md).

Generate a fresh harness with `ruby Tests/prepare_wallet_acceptance.rb` with the Ruby `xcodeproj` gem installed. The script prints its directory, unique isolated Bundle ID and designated simulator UUID. It copies Xcode metadata into a temporary directory and references the current workspace source and installed dependencies. It does not change the production Bundle IDs or Info.plist. The tests refuse to run in an app outside `com.vava.walletacceptance.*` and require a fresh zero-balance wallet.

From the printed harness directory, resolve the Vava QA UDID for this run.

```sh
qa_udid=$(python3 qa_simulator.py) || exit 1
xcodebuild -project Vava.xcodeproj -scheme VavaWalletAcceptance -configuration Debug \
  -destination "platform=iOS Simulator,id=$qa_udid" \
  -derivedDataPath /tmp/vava-wallet-build -resultBundlePath /tmp/vava-wallet-result.xcresult \
  -parallel-testing-enabled NO test
```

Use a new result path for each run. Keep simulator signing enabled. The generated Debug simulator host includes `get-task-allow` so StoreKit Test can load and change its catalog and simulate cancellation. If the simulator log says the test bundle “is not installed for development,” verify that the test host's simulated entitlements include this key and rebuild the harness. Use only the printed isolated Bundle ID for manual purchase checks. Never reset the owner's container or its StoreKit history. Record hashes of the original application's library and wallet before and after the run. Local StoreKit success does not establish Apple sandbox or production readiness.

The recorder retains the StoreKit 1 purchased callback for duplicate delivery. Its display name is `Vava Wallet Test`, and the StoreKit fixture belongs to the test bundle. Run on the designated simulator.

When testing with system dialogs visible, confirm the coin pack on the Xcode purchase sheet, then acknowledge the separate SpringBoard success alert marked `[Environment: Xcode]`. Check Vava's own result, balance and activity after the system alert closes. For cancellation, close the purchase sheet before confirming.

## Historical wallet feedback UI regression

The November 16 results cover the UIKit version tested on that date.

`WalletFeedbackTests.swift` exercises the app through XCTest and local StoreKit Test. It covers the Tutorials learning empty state, deferred approval while Me stays visible, persistent verification failure, recoverable storage failure, startup recovery, failed retry, successful retry, and exactly-once persistence after restart.

Run the four numbered tests together, in order, in a fresh isolated app container. The suite starts with zero coins; the second case credits 800. The third keeps an invalid transaction uncredited, including after retry. The fourth adds 400 only after storage becomes writable again. Do not reset the owner's app or initiate purchases in its container.

Do not clear all StoreKit history after crediting the test wallet: the local test session can reuse transaction identifiers. Before the storage case, remove only the invalid transaction and retain the credited purchase. The test checks that the next purchase has a different identifier.

The acceptance harness uses a UI testing target with this source and `Configuration/VavaCoins.storekit` copied into the test runner's resources. Its app target uses the current App, Assets, and Configuration sources with an isolated Debug Bundle ID. The project's production targets do not include this test file or the StoreKit fixture.

Use the project-specific `Vava QA` simulator. Verification-error injection requires iOS 17 or later. The tests deliberately use StoreKit's error simulation; the app contains no test-only credit or failure hooks. These tests do not establish Apple sandbox or production readiness.

Run this suite with `python3 Tests/run_wallet_feedback.py --harness <isolated-project-directory> --result <unique-result-name>.xcresult --log <log-path>`. The host driver responds to test acknowledgements by backing up the isolated app's single local wallet file and temporarily replacing its path with a nonempty directory. This forces an actual save failure while the app retains its valid in-memory balance. Restoring the file allows the same unfinished transaction to be retried. The driver also restores the backup in its cleanup handler if a test fails. The test runner and app must use the harness target and Bundle IDs specified in the driver. The owner app is never a fixture target.
