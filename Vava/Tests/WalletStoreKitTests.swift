import StoreKit
import StoreKitTest
import XCTest
@testable import Vava

@MainActor final class WalletStoreKitTests: XCTestCase {
    func testPurchaseCancellationAndDuplicateDelivery() async throws {
        continueAfterFailure = false
        let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertTrue((bundle.hasPrefix("com.vava.walletacceptance.") || bundle.hasPrefix("com.vava.h5acceptance.")), "Only run in an isolated app")
        guard (bundle.hasPrefix("com.vava.walletacceptance.") || bundle.hasPrefix("com.vava.h5acceptance.")) else { return }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VavaCoins", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.disableDialogs = true
        defer { session.resetToDefaultState() }

        let account = UUID()
        let wallet = try Wallet(account: account)
        defer { wallet.stop() }
        XCTAssertEqual(wallet.ledger.balance, 0, "A fresh isolated wallet is required")
        XCTAssertTrue(wallet.ledger.entries.isEmpty)
        try await wallet.refresh()
        let pack = try XCTUnwrap(CoinPack.all.first(where: { $0.coins == 400 }))
        let price = try XCTUnwrap(wallet.price(for: pack))
        let recorder = StoreKitTransactionRecorder()
        defer { recorder.stop() }
        let message = try await wallet.buy(pack, price: price)
        XCTAssertEqual(message, "Coins added to your wallet.")
        XCTAssertEqual(wallet.ledger.balance, 400)
        XCTAssertEqual(wallet.ledger.entries.count, 1)
        XCTAssertFalse(wallet.hasPurchaseIssue)

        let transaction = try XCTUnwrap(recorder.purchases.first)
        let transactionID = try XCTUnwrap(transaction.transactionIdentifier)
        XCTAssertEqual(transaction.payment.applicationUsername, account.uuidString)
        XCTAssertEqual(wallet.ledger.entries.first?.id, "apple:\(transactionID)")
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false)
        let file = support.appendingPathComponent("LocalStoreKitWallets/\(account.uuidString).json")
        let afterPurchase = try Data(contentsOf: file)
        print("WALLET_ACCEPTANCE success balance=400 entries=1 transaction=\(transactionID)")

        try await session.setSimulatedError(.generic(.userCancelled), forAPI: StoreKitPurchaseAPI())
        let canceled = try await wallet.buy(pack, price: price)
        XCTAssertEqual(canceled, "Purchase canceled.")
        XCTAssertEqual(wallet.ledger.balance, 400)
        XCTAssertEqual(wallet.ledger.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), afterPurchase)
        try await session.setSimulatedError(nil, forAPI: StoreKitPurchaseAPI())
        print("WALLET_ACCEPTANCE canceled balance=400 entries=1 ledger_unchanged=true")

        // Replay the original StoreKit 1 queue callback through the production update handler.
        // Repeated scans alone would not prove handling of an actual duplicate callback.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { await wallet.receive(transaction) }
            }
            await group.waitForAll()
        }
        await wallet.retryPendingPurchases()
        XCTAssertEqual(wallet.ledger.balance, 400)
        XCTAssertEqual(wallet.ledger.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), afterPurchase)
        XCTAssertFalse(wallet.hasPurchaseIssue)
        print("WALLET_ACCEPTANCE duplicate_callbacks=12 balance=400 entries=1 ledger_unchanged=true")

        wallet.stop()
        let reopened = try Wallet(account: account)
        defer { reopened.stop() }
        await reopened.receive(transaction)
        await reopened.retryPendingPurchases()
        XCTAssertEqual(reopened.ledger.balance, 400)
        XCTAssertEqual(reopened.ledger.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), afterPurchase)
        XCTAssertFalse(reopened.hasPurchaseIssue)
        let persisted = try JSONDecoder().decode(WalletLedger.self, from: Data(contentsOf: file))
        XCTAssertEqual(persisted.balance, 400)
        XCTAssertEqual(persisted.entries.filter { $0.id == "apple:\(transactionID)" }.count, 1)
        print("WALLET_ACCEPTANCE reopen_duplicate balance=400 entries=1 ledger_unchanged=true")

        reopened.stop()
    }
}
