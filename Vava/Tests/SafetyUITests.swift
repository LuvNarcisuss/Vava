import XCTest

@MainActor final class SafetyUITests: XCTestCase {
    private var app: XCUIApplication!
    private let lesson = "Find your ready position"
    private let clip = "Ravne league final"
    private let publisher = "Televizija Uršlja"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--safety-account", UUID().uuidString, "--seed-safety"]
        app.launch()
        XCTAssertTrue(app.buttons["Academy"].waitForExistence(timeout: 15))
        app.launchArguments.removeLast()
    }

    private func tap(_ title: String) {
        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), title)
        button.tap()
    }

    private func absent(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    private func lessonButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", lesson)).firstMatch
    }

    private func settings(_ section: String) {
        tap("Me")
        tap("Settings")
        tap(section)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLessonReportRefreshRestartAndLongPressUndo() {
        XCTAssertTrue(lessonButton().exists)
        tap("More lesson actions")
        tap("Report lesson")
        tap("Something else")
        absent(lessonButton())
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Academy"].waitForExistence(timeout: 10))
        absent(lessonButton())
        settings("Reported content")
        let report = lessonButton()
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.press(forDuration: 1.2)
        tap("Cancel report")
        XCTAssertTrue(app.alerts["Cancel report?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel report"].tap()
        XCTAssertTrue(app.staticTexts["No reported content."].waitForExistence(timeout: 5))
        tap("Back")
        tap("Back")
        tap("Academy")
        XCTAssertTrue(lessonButton().waitForExistence(timeout: 5))
        capture("Lesson restored after confirmed long-press undo")
    }

    func testVideoReportRefreshSearchSavedAndUndo() {
        tap("Shorts")
        XCTAssertTrue(app.staticTexts[clip].waitForExistence(timeout: 5))
        tap("More clip actions")
        tap("Report clip")
        tap("Something else")
        absent(app.staticTexts[clip])
        let progress = app.sliders["Playback position"]
        let initialPosition = progress.value as? String ?? ""
        expectation(for: NSPredicate(format: "value != %@", initialPosition), evaluatedWith: progress)
        waitForExpectations(timeout: 8)
        tap("Search clips")
        let search = app.textFields["Find a player, rally or match"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(clip)
        absent(app.buttons[clip])
        tap("Close search")
        tap("Me")
        tap("Saved")
        absent(app.buttons[clip])
        tap("Settings")
        tap("Reported content")
        let report = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", clip)).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.press(forDuration: 1.2)
        tap("Cancel report")
        app.alerts.buttons["Cancel report"].tap()
        tap("Back")
        tap("Back")
        tap("Saved")
        XCTAssertTrue(app.buttons[clip].waitForExistence(timeout: 5))
        capture("Reported video restored in Saved")
    }

    func testBlockFromAcademyProfileCancelAndConfirm() {
        tap("Tom Lodziak")
        tap("Block")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Back"].exists)
        tap("Block")
        app.alerts.buttons["Block"].tap()
        XCTAssertTrue(app.alerts["Blocked"].waitForExistence(timeout: 5))
        capture("Block success above refreshed Academy root")
        app.alerts.buttons["OK"].tap()
        absent(app.buttons["Back"])
        absent(lessonButton())
        tap("Me")
        tap("Academy")
        absent(app.alerts["Blocked"])
    }

    func testBlockFromShortsProfileAndLongPressUnblock() {
        tap("Shorts")
        tap("View \(publisher) profile")
        tap("Block")
        app.alerts.buttons["Block"].tap()
        XCTAssertTrue(app.alerts["Blocked"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        absent(app.buttons["Back"])
        absent(app.staticTexts[clip])
        let progress = app.sliders["Playback position"]
        let initialPosition = progress.value as? String ?? ""
        expectation(for: NSPredicate(format: "value != %@", initialPosition), evaluatedWith: progress)
        waitForExpectations(timeout: 8)
        settings("Blocked accounts")
        let person = app.buttons[publisher]
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.press(forDuration: 1.2)
        tap("Unblock")
        app.alerts.buttons["Unblock"].tap()
        XCTAssertTrue(app.staticTexts["No blocked accounts."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Back"].exists)
        capture("Unblock stays on the management page")
    }

    func testBlockFromChatsReturnsToFilteredInbox() {
        tap("Chats")
        tap(publisher)
        tap("View profile")
        tap("Block")
        app.alerts.buttons["Block"].tap()
        XCTAssertTrue(app.alerts["Blocked"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        absent(app.buttons["Back"])
        absent(app.buttons[publisher])
        XCTAssertTrue(app.staticTexts["Keep the rally going"].exists)
        capture("Blocked publisher removed from Chats")
    }

    func testBlockFromLessonDetailReturnsToAcademy() {
        lessonButton().tap()
        tap("More lesson actions")
        tap("Block publisher")
        app.alerts.buttons["Block"].tap()
        XCTAssertTrue(app.alerts["Blocked"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        absent(app.buttons["Back"])
        absent(lessonButton())
        XCTAssertTrue(app.buttons["Academy"].exists)
    }

    func testBlockFromShortsMenuResumesPlayback() {
        tap("Shorts")
        tap("More clip actions")
        tap("Block publisher")
        app.alerts.buttons["Block"].tap()
        XCTAssertTrue(app.alerts["Blocked"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        absent(app.staticTexts[clip])
        absent(app.buttons["Back"])
        let progress = app.sliders["Playback position"]
        let initialPosition = progress.value as? String ?? ""
        expectation(for: NSPredicate(format: "value != %@", initialPosition), evaluatedWith: progress)
        waitForExpectations(timeout: 8)
        capture("Shorts menu block resumes eligible playback")
    }

    func testWalletSummaryHasCompactLayout() {
        tap("Me")
        tap("Wallet  ·  0 coins")
        let summary = app.descendants(matching: .any).matching(identifier: "Coin balance").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertLessThan(summary.frame.height, 150)
        XCTAssertGreaterThan(summary.frame.height, 44)
        capture("Compact wallet balance card")
    }

    func testReportFailureKeepsReasonForRetryWithoutHidingLesson() {
        app.terminate()
        app.launchArguments.append("--fail-safety-writes")
        app.launch()
        XCTAssertTrue(lessonButton().waitForExistence(timeout: 10))
        tap("More lesson actions")
        tap("Report lesson")
        tap("Something else")
        XCTAssertTrue(app.alerts["Report not saved"].waitForExistence(timeout: 5))
        app.alerts.buttons["Retry"].tap()
        XCTAssertTrue(app.alerts["Report not saved"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(lessonButton().exists)
        capture("Failed report preserves content and exposes retry")
    }

    func testBlockFailureKeepsProfileAndShowsError() {
        app.terminate()
        app.launchArguments.append("--fail-safety-writes")
        app.launch()
        tap("Tom Lodziak")
        tap("Block")
        app.alerts.buttons["Block"].tap()
        XCTAssertTrue(app.alerts["Please try again"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Back"].exists)
        XCTAssertTrue(app.buttons["Block"].exists)
        absent(app.alerts["Blocked"])
        capture("Failed block keeps the current profile")
    }
}
