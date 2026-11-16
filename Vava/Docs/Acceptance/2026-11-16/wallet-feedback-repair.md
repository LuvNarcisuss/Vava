# Wallet feedback and learning copy repair

November 16, 2026, Asia/Shanghai

## Changes

- Me observes wallet changes, updating the visible balance when a deferred purchase arrives without requiring navigation or refresh.
- Delivery failures retain per-transaction state and emit a receipt-free diagnostic log. Me directs the user to Wallet; Wallet displays a persistent purchase-attention card and Retry purchases action. Startup, opening Wallet, and pull-to-refresh check unfinished transactions. A successful verified, saved delivery clears only its own failure.
- Unverified transaction fields only scope feedback to the current account and environment. They never authorize credit. Transaction verification, account matching, atomic saving, deduplication, and finish-after-save remain in place.
- Tutorials now presents My learning, with an empty-state prompt to start a lesson or unlock a practice plan. The unsupported tutorial-publishing message is removed.

## Targeted regression

Environment: Xcode 26.0.1, Vava UI Acceptance, iPhone 17 Pro, iOS 26.0.1, simulator `C6BBDAF1-EF03-4F2E-980F-CB8C472367D6`. All purchase and fault-injection cases used the isolated `com.vava.pingpong.acceptance.nov13` app.

The original source failed three behavior checks: the old Tutorials message remained, deferred approval did not refresh the visible Me balance, and an unverified background delivery produced no visible warning. The ledger confirmed the invalid delivery was uncredited.

The final four-case suite passed:

1. Tutorials displays the learning empty state.
2. Approving 800 coins while Me remains visible immediately updates its wallet button; one purchase entry is shown.
3. Invalid transaction verification produces a Me notice and Wallet retry card. The failure is rediscovered after app restart. Failed retries leave the warning and 800-coin balance unchanged.
4. A real storage write failure leaves a verified 400-coin transaction unfinished and the balance at 800. A failed retry retains the warning. Restoring the original ledger file and retrying credits exactly 400, clears the warning, and updates Me to 1,200. Restart retains exactly one 800-coin entry and one 400-coin entry.

The storage fixture backs up only the isolated ledger, temporarily occupies its path with a nonempty directory, and restores the original file before retry. Its host driver also restores the backup on failure. No app-side test credit or failure hooks were added.

Early test-harness iterations incorrectly expected a simulated invalid signature to become valid after disabling injection, and cleared StoreKit history while retaining a credited ledger, allowing test transaction IDs to repeat. The final tests separate permanent verification failure from recoverable storage failure and retain credited transaction IDs. App verification and deduplication were not weakened to accommodate the tests.

The committed tests and runner are described in [Tests/README.md](../../../Tests/README.md). Result bundles are under `/tmp/vava-acceptance.0z0B6Y`; the expected pre-fix failures are in `feedback-red-behavior.xcresult`, and the four-case passing run is `feedback-final-green.xcresult`.

## Full regression after repair

The current App sources passed all 17 existing acceptance cases, for 21 distinct passing cases including the four targeted regressions:

| Result bundle | Passed | Failed | Coverage |
| --- | ---: | ---: | --- |
| `feedback-final-green.xcresult` | 4 | 0 | Wallet feedback and learning copy |
| `feedback-full-main.xcresult` | 11 | 0 | Standard-size full function flows |
| `feedback-full-accessibility.xcresult` | 1 | 0 | Large-text wallet and profile |
| `feedback-full-wallet.xcresult` | 3 | 0 | Ordinary launch, repeated purchases, failure, deferred approval and sign-in |
| `feedback-full-packs.xcresult` | 2 | 0 | Full simulator reboot, original wallet, all nine coin packs and persistence |

All nine local packs credited their expected amounts. The isolated balance reached 174,500 with 13 purchase entries and survived restart. The latest workspace Debug build was installed over the original app. Its original wallet still displayed 800 coins and one purchase entry after the simulator reboot and final checks. Application Support file hashes matched the pre-task snapshot. The simulator's original `large` text size was restored.

The full suite also rechecked consent, playback, search, likes/saves, private comments, source controls, course progress and unlocking, replay links and sharing, contacts and drafts, profile edits, Photos import/removal, sign-out, isolated account deletion, refresh and media credits. No new product failure was observed in those flows.

## Validation boundary

Debug and Release simulator builds succeeded. The static verifier passed 536 checks; strict recursive Swift format lint, test-driver syntax and diff whitespace checks passed. These are local StoreKit Test results, not Apple sandbox or production payment certification. The filesystem fixture exercises a genuine save failure, not physical disk exhaustion. Existing compile warnings are outside this repair.
