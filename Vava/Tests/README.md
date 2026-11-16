# Wallet feedback UI regression

`WalletFeedbackTests.swift` exercises the app through XCTest and local StoreKit Test. It covers the Tutorials learning empty state, deferred approval while Me stays visible, persistent verification failure, recoverable storage failure, startup recovery, failed retry, successful retry, and exactly-once persistence after restart.

Run the four numbered tests together, in order, in a fresh isolated app container. The suite starts with zero coins; the second case credits 800. The third keeps an invalid transaction uncredited, including after retry. The fourth adds 400 only after storage becomes writable again. Do not reset the owner's app or initiate purchases in its container.

Do not clear all StoreKit history after crediting the test wallet: the local test session can reuse transaction identifiers. Before the storage case, remove only the invalid transaction and retain the credited purchase. The test checks that the next purchase has a different identifier.

The acceptance harness uses a UI testing target with this source and `Configuration/VavaCoins.storekit` copied into the test runner's resources. Its app target uses the current App, Assets, and Configuration sources with an isolated Debug Bundle ID. The project's production targets do not include this test file or the StoreKit fixture.

Use the project-specified Vava UI Acceptance simulator. Verification-error injection requires iOS 17 or later. The tests deliberately use StoreKit's error simulation; the app contains no test-only credit or failure hooks. These tests do not establish Apple sandbox or production readiness.

Run this suite with `python3 Tests/run_wallet_feedback.py --harness <isolated-project-directory> --result <unique-result-name>.xcresult --log <log-path>`. The host driver responds to test acknowledgements by backing up the isolated app's single local wallet file and temporarily replacing its path with a nonempty directory. This forces an actual save failure while the app retains its valid in-memory balance. Restoring the file allows the same unfinished transaction to be retried. The driver also restores the backup in its cleanup handler if a test fails. The test runner and app must use the harness target and Bundle IDs specified in the driver. The owner app is never a fixture target.
