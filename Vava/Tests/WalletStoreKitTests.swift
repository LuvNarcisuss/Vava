import StoreKit
import StoreKitTest
import UIKit
import XCTest
@testable import Vava

@MainActor final class WalletStoreKitTests: XCTestCase {
    func testEmptyCatalogIsFailureAndCanRecover() async throws {
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.vava.walletacceptance.") == true else {
            XCTFail("Catalog tests require an isolated application.")
            return
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VavaCoins", withExtension: "storekit"))
        var configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        configuration["products"] = []
        let emptyFixture = FileManager.default.temporaryDirectory.appendingPathComponent("EmptyCatalog.storekit")
        try JSONSerialization.data(withJSONObject: configuration).write(to: emptyFixture)
        defer { try? FileManager.default.removeItem(at: emptyFixture) }
        let emptySession = try SKTestSession(contentsOf: emptyFixture)
        emptySession.disableDialogs = true
        let wallet = try Wallet(account: UUID())
        defer { wallet.stop() }
        do {
            try await wallet.refresh()
            XCTFail("An empty StoreKit catalog must not report a successful refresh.")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        XCTAssertTrue(CoinPack.all.allSatisfy { wallet.price(for: $0) == nil })
        XCTAssertEqual(wallet.catalogStatus, .unavailable)
        var partial = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        partial["products"] = Array(try XCTUnwrap(partial["products"] as? [[String: Any]]).prefix(1))
        let partialFixture = FileManager.default.temporaryDirectory.appendingPathComponent("PartialCatalog.storekit")
        try JSONSerialization.data(withJSONObject: partial).write(to: partialFixture)
        defer { try? FileManager.default.removeItem(at: partialFixture) }
        let partialSession = try SKTestSession(contentsOf: partialFixture)
        try await wallet.refresh()
        XCTAssertEqual(wallet.catalogStatus, .partial)
        XCTAssertEqual(CoinPack.all.filter { wallet.price(for: $0) != nil }.count, 1)
        let session = try SKTestSession(contentsOf: fixture)
        session.disableDialogs = true
        try await wallet.refresh()
        XCTAssertEqual(CoinPack.all.filter { wallet.price(for: $0) != nil }.count, 9)
        XCTAssertEqual(wallet.catalogStatus, .ready)
        XCTAssertEqual(wallet.ledger.balance, 0)
        XCTAssertTrue(wallet.ledger.entries.isEmpty)
        withExtendedLifetime((emptySession, partialSession, session)) {}
    }

    func testPurchaseCancellationAndDuplicateDelivery() async throws {
        continueAfterFailure = false
        let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
        guard bundle.hasPrefix("com.vava.walletacceptance.") else {
            XCTFail("Purchase tests require an isolated wallet test application.")
            return
        }
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


extension WalletStoreKitTests {
    func testWalletScreenCheckout() async throws {
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.vava.walletacceptance.") == true else {
            XCTFail("Checkout requires an isolated application.")
            return
        }
        let window = try XCTUnwrap((UIApplication.shared.delegate as? VavaApplication)?.window)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VavaCoins", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.disableDialogs = true
        defer { session.resetToDefaultState() }

        func button(_ label: String) async throws -> UIButton {
            try await waitFor(label) {
                self.descendants(of: window).compactMap { $0 as? UIButton }.first {
                    $0.isEnabled && ($0.accessibilityLabel == label || $0.currentTitle == label)
                }
            }
        }

        func checkout(expected: String) async throws {
            let pack = try await button("400 coins")
            let price = try XCTUnwrap(pack.accessibilityValue)
            pack.sendActions(for: .touchUpInside)
            let buy = try await button("Buy for " + price)
            buy.sendActions(for: .touchUpInside)
            let alert: UIAlertController = try await waitFor(expected) {
                let tabs = window.rootViewController as? UITabBarController
                let navigation = tabs?.selectedViewController as? UINavigationController
                let presented = navigation?.topViewController?.presentedViewController
                    ?? navigation?.presentedViewController ?? tabs?.presentedViewController
                return presented as? UIAlertController
            }
            XCTAssertEqual(alert.message, expected)
            await withCheckedContinuation { done in
                alert.dismiss(animated: false) { done.resume() }
            }
        }

        // Keep StoreKit acceptance independent of company credentials and network availability.
        let owner = UUID()
        let library = try LocalLibrary(account: owner)
        _ = try library.open(revision: Agreement.revision, accepted: true)
        let catalog: Catalog = try XCTUnwrap(Bundle.main.decode("catalog"))
        let context = try AppContext(library: library, wallet: Wallet(account: owner), catalog: catalog)
        let previousRoot = window.rootViewController
        defer {
            context.wallet.stop()
            window.rootViewController = previousRoot
        }
        window.rootViewController = Dock(context)
        let profile = try await button("Me")
        profile.sendActions(for: .touchUpInside)
        let tabs = try XCTUnwrap(window.rootViewController as? Dock)
        let navigation = try XCTUnwrap(tabs.selectedViewController as? UINavigationController)
        let screen = try XCTUnwrap(navigation.topViewController as? ProfileScreen)
        let initialBalance = screen.context.wallet.ledger.balance
        let wallet = try await button("Wallet  ·  " + initialBalance.formatted() + " coins")
        wallet.sendActions(for: .touchUpInside)
        for pack in CoinPack.all {
            let offer = try await button(pack.coins.formatted() + " coins")
            let price = try XCTUnwrap(offer.accessibilityValue)
            XCTAssertFalse(price.isEmpty)
            XCTAssertNotEqual(price, "Unavailable")
        }

        func purchaseRows() -> Int {
            descendants(of: window).compactMap { ($0 as? UILabel)?.text }
                .filter { $0 == "Coin pack  ·  +400 coins" }.count
        }
        let initialRows = purchaseRows()
        try await checkout(expected: "Coins added to your wallet.")
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: StoreKitPurchaseAPI())
        try await checkout(expected: "Purchase canceled.")
        XCTAssertEqual(purchaseRows(), initialRows + 1)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Wallet after purchase and cancellation"
        attachment.lifetime = .keepAlways
        add(attachment)
        let back = try await button("Back")
        back.sendActions(for: .touchUpInside)
        _ = try await button("Wallet  ·  " + (initialBalance + 400).formatted() + " coins")
    }

    private func descendants(of view: UIView) -> [UIView] {
        guard !view.isHidden else { return [] }
        return [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func waitFor<T>(_ description: String, value: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(30)
        repeat {
            if let result = value() { return result }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw NSError(domain: "WalletAcceptance", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for " + description])
    }
}
