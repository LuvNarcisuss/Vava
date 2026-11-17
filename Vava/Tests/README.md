# Wallet acceptance tests

## Current React Native and StoreKit coverage

`WalletStoreKitTests.swift` runs against the production Wallet implementation inside an isolated build of the current React Native application. It verifies a successful 400-coin purchase, cancellation with identical persisted bytes, 12 repeated callbacks carrying the same StoreKit-verified transaction, and another duplicate after reopening the wallet. The transaction comes from StoreKit Test; the test does not manufacture a verified result or bypass validation. A follow-up manual pass exercises the React Native purchase sheet, success state, cancellation and process restart. See [the acceptance record](../Docs/WalletStoreKitAcceptance.md).

Generate a fresh harness with `ruby Tests/prepare_wallet_acceptance.rb` after installing the normal workspace dependencies. The script prints its directory, unique isolated Bundle ID and designated simulator UUID. It copies Xcode metadata into a temporary directory and references the current workspace source and installed dependencies. It does not change the production Bundle IDs or Info.plist. The tests refuse to run in an app outside `com.vava.walletacceptance.*` and require a fresh zero-balance wallet.

From the printed harness directory, run:

```sh
xcodebuild -workspace Vava.xcworkspace -scheme VavaWalletAcceptance -configuration Debug \
  -destination 'platform=iOS Simulator,id=C6BBDAF1-EF03-4F2E-980F-CB8C472367D6' \
  -derivedDataPath /tmp/vava-wallet-build -resultBundlePath /tmp/vava-wallet-result.xcresult \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO
```

Use a new result path for each run. Keep Metro serving the current workspace for the React Native host. Use only the printed isolated Bundle ID for manual purchase checks. Never reset the owner's container or its StoreKit history. Record hashes of the original application's library and wallet before and after the run. Local StoreKit success does not establish Apple sandbox or production readiness.

The harness alone enables `SKIncludeConsumableInAppPurchaseHistory` so the test can retrieve a finished consumable's signed result for duplicate delivery. Its display name is `Vava Wallet Test`, and the StoreKit fixture belongs to the test bundle. The test ends with a synthetic local profile that can be reopened for manual UI acceptance. Run on the designated simulator; finished-consumable history requires iOS 18 or later.

## Historical wallet feedback UI regression

The current application uses React Native. This historical UIKit UI suite has not yet been adapted to the new accessibility labels or rerun against the migrated interface. See `Docs/ReactNativeAcceptance.md` for the November 16 migration coverage; do not treat earlier harness results as current migration acceptance.

`WalletFeedbackTests.swift` exercises the app through XCTest and local StoreKit Test. It covers the Tutorials learning empty state, deferred approval while Me stays visible, persistent verification failure, recoverable storage failure, startup recovery, failed retry, successful retry, and exactly-once persistence after restart.

Run the four numbered tests together, in order, in a fresh isolated app container. The suite starts with zero coins; the second case credits 800. The third keeps an invalid transaction uncredited, including after retry. The fourth adds 400 only after storage becomes writable again. Do not reset the owner's app or initiate purchases in its container.

Do not clear all StoreKit history after crediting the test wallet: the local test session can reuse transaction identifiers. Before the storage case, remove only the invalid transaction and retain the credited purchase. The test checks that the next purchase has a different identifier.

The acceptance harness uses a UI testing target with this source and `Configuration/VavaCoins.storekit` copied into the test runner's resources. Its app target uses the current App, Assets, and Configuration sources with an isolated Debug Bundle ID. The project's production targets do not include this test file or the StoreKit fixture.

Use the project-specified Vava UI Acceptance simulator. Verification-error injection requires iOS 17 or later. The tests deliberately use StoreKit's error simulation; the app contains no test-only credit or failure hooks. These tests do not establish Apple sandbox or production readiness.

Run this suite with `python3 Tests/run_wallet_feedback.py --harness <isolated-project-directory> --result <unique-result-name>.xcresult --log <log-path>`. The host driver responds to test acknowledgements by backing up the isolated app's single local wallet file and temporarily replacing its path with a nonempty directory. This forces an actual save failure while the app retains its valid in-memory balance. Restoring the file allows the same unfinished transaction to be retried. The driver also restores the backup in its cleanup handler if a test fails. The test runner and app must use the harness target and Bundle IDs specified in the driver. The owner app is never a fixture target.

## Local H5 acceptance

The current presentation renders in WKWebView. After owner authorization, run `npm run build:web`, both TypeScript checks, then `ruby Tests/prepare_h5_acceptance.rb`. In its printed temporary directory use `FORCE_BUNDLING=1 xcodebuild -workspace Vava.xcworkspace -scheme VavaH5Acceptance -configuration Debug -destination 'platform=iOS Simulator,id=C6BBDAF1-EF03-4F2E-980F-CB8C472367D6' -derivedDataPath /tmp/vava-h5-build -resultBundlePath /tmp/vava-h5-result.xcresult test`. Use a fresh isolated application and result path for each complete run.

The hosted tests interact with the real local document through WKWebView, record screenshots, check packaged images and video, exercise navigation and native state writes, and buy/cancel through H5 using StoreKit Test. They do not impersonate a backend or manufacture signed transactions. Capture the original app's JSON file set and hashes before and after; never clear its container. See `Docs/LocalH5Migration.md` for current outcomes and remaining physical-device checks.
