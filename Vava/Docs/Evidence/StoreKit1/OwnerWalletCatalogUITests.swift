import XCTest

final class VavaTouchTests: XCTestCase {
    @MainActor func testExistingWalletCatalogWithoutPurchasing() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "im.seex.sao2")
        XCTAssertNotEqual(app.state, .notRunning, "Start the current application from Xcode with its StoreKit configuration first.")
        app.activate()
        let consent = app.descendants(matching: .any).matching(identifier: "Accept the agreements").firstMatch
        if consent.waitForExistence(timeout: 5) {
            consent.tap()
            app.buttons["Log in"].firstMatch.tap()
        }
        if !app.buttons["400 coins, $0.99"].firstMatch.exists {
            let academy = app.staticTexts["Build a better point."].firstMatch
            XCTAssertTrue(academy.waitForExistence(timeout: 30), app.debugDescription)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.955)).tap()
            let wallet = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wallet ·'")).firstMatch
            XCTAssertTrue(wallet.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(wallet.label, "Wallet · 1,200 coins")
            wallet.tap()
        }
        for label in ["400 coins, $0.99", "800 coins, $1.99", "2450 coins, $4.99", "5150 coins, $9.99", "10800 coins, $19.99", "16800 coins, $29.99", "29400 coins, $49.99", "42600 coins, $69.99", "63700 coins, $99.99"] {
            XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 20), label + "\n" + app.debugDescription)
            XCTAssertTrue(app.buttons[label].firstMatch.isEnabled)
        }
        XCTAssertTrue(app.staticTexts["1,200"].firstMatch.exists, app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Original wallet catalog with unchanged balance"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
