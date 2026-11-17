import StoreKit
import StoreKitTest
import XCTest
@testable import Vava

@MainActor final class WalletStoreKitTests: XCTestCase {
    func testPurchaseCancellationAndDuplicateDelivery() async throws {
        continueAfterFailure = false
        let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertTrue(bundle.hasPrefix("com.vava.walletacceptance."), "Only run in an isolated app")
        guard bundle.hasPrefix("com.vava.walletacceptance.") else { return }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VavaCoins", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.disableDialogs = true
        defer { session.resetToDefaultState() }

        let library = try LocalLibrary()
        let profile = try library.open(revision: "2026-11-13.2", accepted: true)
        try library.signOut()
        let wallet = try Wallet(account: profile.id)
        defer { wallet.stop() }
        XCTAssertEqual(wallet.ledger.balance, 0, "A fresh isolated wallet is required")
        XCTAssertTrue(wallet.ledger.entries.isEmpty)
        try await wallet.refresh()
        let pack = try XCTUnwrap(CoinPack.all.first(where: { $0.coins == 400 }))
        let price = try XCTUnwrap(wallet.price(for: pack))
        let message = try await wallet.buy(pack, price: price)
        XCTAssertEqual(message, "Coins added to your wallet.")
        XCTAssertEqual(wallet.ledger.balance, 400)
        XCTAssertEqual(wallet.ledger.entries.count, 1)
        XCTAssertFalse(wallet.hasPurchaseIssue)

        let latest = await Transaction.latest(for: pack.productID)
        let verified = try XCTUnwrap(latest)
        guard case .verified(let transaction) = verified else {
            XCTFail("StoreKit must supply a verified transaction")
            return
        }
        XCTAssertEqual(transaction.environment, .xcode)
        XCTAssertEqual(transaction.appAccountToken, profile.id)
        XCTAssertEqual(wallet.ledger.entries.first?.id, "apple:\(transaction.id)")
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false)
        let file = support.appendingPathComponent("LocalStoreKitWallets/\(profile.id.uuidString).json")
        let afterPurchase = try Data(contentsOf: file)
        print("WALLET_ACCEPTANCE success balance=400 entries=1 transaction=\(transaction.id)")

        try await session.setSimulatedError(.generic(.userCancelled), forAPI: StoreKitPurchaseAPI())
        let canceled = try await wallet.buy(pack, price: price)
        XCTAssertEqual(canceled, "Purchase canceled.")
        XCTAssertEqual(wallet.ledger.balance, 400)
        XCTAssertEqual(wallet.ledger.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), afterPurchase)
        try await session.setSimulatedError(nil, forAPI: StoreKitPurchaseAPI())
        print("WALLET_ACCEPTANCE canceled balance=400 entries=1 ledger_unchanged=true")

        // Replay the original, signed StoreKit result through the production update handler.
        // Repeated scans alone would not prove handling of an actual duplicate callback.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { await wallet.receive(verified) }
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
        let reopened = try Wallet(account: profile.id)
        defer { reopened.stop() }
        await reopened.receive(verified)
        await reopened.retryPendingPurchases()
        XCTAssertEqual(reopened.ledger.balance, 400)
        XCTAssertEqual(reopened.ledger.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), afterPurchase)
        XCTAssertFalse(reopened.hasPurchaseIssue)
        let persisted = try JSONDecoder().decode(WalletLedger.self, from: Data(contentsOf: file))
        XCTAssertEqual(persisted.balance, 400)
        XCTAssertEqual(persisted.entries.filter { $0.id == "apple:\(transaction.id)" }.count, 1)
        print("WALLET_ACCEPTANCE reopen_duplicate balance=400 entries=1 ledger_unchanged=true")

        reopened.stop()
        _ = try library.open(revision: "2026-11-13.2", accepted: false)
    }
}
