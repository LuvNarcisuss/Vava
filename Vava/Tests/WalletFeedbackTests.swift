import StoreKitTest
import XCTest

final class WalletFeedbackTests: XCTestCase {
    private let app = XCUIApplication()
    private let issue = "Some purchases could not be added to your wallet. Open Wallet to retry."

    override func setUpWithError() throws { continueAfterFailure = false }

    private func tap(_ name: String) {
        let alert = app.alerts.buttons[name].firstMatch
        let button = alert.exists ? alert : app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), name)
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        button.tap()
    }

    private func launch() {
        app.launchEnvironment["VAVA_LOCAL_STOREKIT"] = ""
        app.launch()
        if app.buttons["Continue"].exists {
            tap("Accept the agreements")
            tap("Continue")
        }
    }

    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VavaCoins", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        return session
    }

    private func requestApproval(coins: String, balance: String, session: SKTestSession) throws -> UInt {
        tap("Me")
        tap("Wallet  ·  " + balance + " coins")
        let pack = app.buttons[coins + " coins"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in pack.exists && pack.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        tap(coins + " coins")
        tap("Buy for " + (try XCTUnwrap(pack.value as? String)))
        XCTAssertTrue(app.staticTexts["Waiting for purchase approval."].waitForExistence(timeout: 10))
        tap("OK")
        tap("Back")
        XCTAssertTrue(app.buttons["Wallet  ·  " + balance + " coins"].exists)
        return try XCTUnwrap(session.allTransactions().first(where: { $0.state == .deferred })).identifier
    }

    func test01TutorialsDescribeLearning() {
        launch()
        tap("Me")
        tap("Tutorials")
        XCTAssertFalse(app.staticTexts["You haven’t published any tutorials."].exists)
        XCTAssertTrue(app.staticTexts["My learning"].exists)
        XCTAssertTrue(app.staticTexts["Start a lesson or unlock a practice plan to see it here."].exists)
    }

    func test02DeferredCreditRefreshesVisibleProfile() throws {
        let session = try session()
        session.clearTransactions()
        session.askToBuyEnabled = true
        defer { session.resetToDefaultState() }
        launch()
        let transaction = try requestApproval(coins: "800", balance: "0", session: session)
        try session.approveAskToBuyTransaction(identifier: transaction)
        XCTAssertTrue(app.buttons["Wallet  ·  800 coins"].waitForExistence(timeout: 15))
        tap("Wallet  ·  800 coins")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Coin pack  ·  +800 coins").count, 1)
    }

    @MainActor
    func test03InvalidTransactionRemainsUncredited() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Requires StoreKit verification failure injection") }
        let session = try session()
        session.askToBuyEnabled = true
        defer { session.resetToDefaultState() }
        launch()
        let transaction = try requestApproval(coins: "400", balance: "800", session: session)
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: StoreKitVerificationAPI())
        try session.approveAskToBuyTransaction(identifier: transaction)
        guard app.staticTexts[issue].waitForExistence(timeout: 15) else {
            XCTFail("A failed background delivery must be visible on Me")
            return
        }
        XCTAssertTrue(app.buttons["Wallet  ·  800 coins"].exists)
        app.terminate()
        app.launch()
        tap("Me")
        XCTAssertTrue(app.staticTexts[issue].waitForExistence(timeout: 15))
        tap("Wallet  ·  800 coins")
        XCTAssertTrue(app.buttons["Retry purchases"].waitForExistence(timeout: 10))
        tap("Retry purchases")
        XCTAssertTrue(app.staticTexts["Purchase needs attention"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Coin pack  ·  +400 coins"].exists)
        try await session.setSimulatedError(nil, forAPI: StoreKitVerificationAPI())
        tap("Retry purchases")
        XCTAssertTrue(app.staticTexts["Purchase needs attention"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Coin pack  ·  +400 coins"].exists)
        tap("Back")
        XCTAssertTrue(app.buttons["Wallet  ·  800 coins"].exists)
        XCTAssertTrue(app.staticTexts[issue].exists)
    }

    private func storageFixture(_ action: String) throws {
        let acknowledgement = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wallet-fixture-ack")
        print("VAVA_WALLET_FIXTURE " + action + " " + acknowledgement.path)
        fflush(stdout)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: acknowledgement.path) },
            object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 30) == .completed else {
            throw NSError(domain: "WalletFixtureTimeout", code: 1)
        }
        try FileManager.default.removeItem(at: acknowledgement)
    }

    func test04StorageFailureRetriesWithoutRestartOrDuplicateCredit() throws {
        let session = try session()
        for transaction in session.allTransactions() where transaction.productIdentifier == "ampqtftkneoumheh" {
            try session.deleteTransaction(identifier: transaction.identifier)
        }
        let credited = try XCTUnwrap(
            session.allTransactions().first(where: { $0.productIdentifier == "xtvhwdsgjloktbwl" }))
        session.askToBuyEnabled = true
        defer { session.resetToDefaultState() }
        launch()
        let transaction = try requestApproval(coins: "400", balance: "800", session: session)
        XCTAssertNotEqual(
            transaction, credited.identifier, "A new purchase must not reuse a credited transaction ID")
        print("TEST TRANSACTIONS: credited=\(credited.identifier), pending=\(transaction)")
        try storageFixture("BLOCK")
        defer { try? storageFixture("RESTORE") }
        try session.approveAskToBuyTransaction(identifier: transaction)
        XCTAssertTrue(app.staticTexts[issue].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Wallet  ·  800 coins"].exists)
        tap("Wallet  ·  800 coins")
        tap("Retry purchases")
        XCTAssertTrue(app.staticTexts["Purchase needs attention"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Coin pack  ·  +400 coins"].exists)
        try storageFixture("RESTORE")
        tap("Retry purchases")
        XCTAssertTrue(app.staticTexts["Coin pack  ·  +400 coins"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Retry purchases"].exists)
        tap("Back")
        XCTAssertTrue(app.buttons["Wallet  ·  1,200 coins"].exists)
        XCTAssertFalse(app.staticTexts[issue].exists)
        app.terminate()
        app.launch()
        tap("Me")
        tap("Wallet  ·  1,200 coins")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Coin pack  ·  +400 coins").count, 1)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Coin pack  ·  +800 coins").count, 1)
    }

}
