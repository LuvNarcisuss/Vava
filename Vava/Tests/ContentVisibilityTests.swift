import UIKit
import XCTest

@testable import Vava

@MainActor final class ContentVisibilityTests: XCTestCase {
    private func makeContext() throws -> AppContext {
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.vava.walletacceptance.") == true else {
            throw XCTSkip("Safety tests require an isolated application.")
        }
        let library = try LocalLibrary(account: UUID())
        let owner = try library.open(revision: "2026-11-13.2", accepted: true)
        let catalog: Catalog = try XCTUnwrap(Bundle.main.decode("catalog"))
        return try AppContext(library: library, wallet: Wallet(account: owner.id), catalog: catalog)
    }

    func testReportAndBlockUndoRemainIndependentInBothOrders() throws {
        for unblockFirst in [true, false] {
            let context = try makeContext()
            defer { context.wallet.stop() }
            let clip = try XCTUnwrap(context.catalog.shorts.first)
            try context.change(clip.id, kind: .save, enabled: true)
            try context.report(clip.id, reason: .other)
            try context.setBlocked(clip.author, enabled: true)
            XCTAssertFalse(context.state.canShow(clip))
            if unblockFirst {
                try context.setBlocked(clip.author, enabled: false)
            } else {
                try context.cancelReport(clip.id)
            }
            XCTAssertFalse(context.state.canShow(clip))
            try context.reload()
            XCTAssertFalse(context.state.canShow(clip))
            if unblockFirst {
                try context.cancelReport(clip.id)
            } else {
                try context.setBlocked(clip.author, enabled: false)
            }
            XCTAssertTrue(context.state.canShow(clip))
            XCTAssertTrue(context.state.saves.contains(clip.id))
            XCTAssertEqual(try context.library.safetyEvents().count, 4)
            let reopened = try LocalLibrary(account: context.state.me.id)
            XCTAssertEqual(try reopened.safetyEvents().count, 4)
            XCTAssertTrue(try reopened.state().canShow(clip))
        }
    }

    func testMeCountsOnlyActivityFromOtherPlayers() throws {
        let context = try makeContext()
        defer { context.wallet.stop() }
        let playerID = "player:" + UUID().uuidString
        try context.library.setFollowing(playerID, enabled: true)
        XCTAssertTrue(try context.library.state().followers.isEmpty)
        try context.library.recordIncomingFollow(from: playerID, enabled: true)
        try context.library.recordIncomingFollow(from: playerID, enabled: true)
        try context.reload()
        XCTAssertEqual(context.state.followers, [playerID])
        try context.library.recordIncomingFollow(from: playerID, enabled: false)
        XCTAssertTrue(try context.library.state().followers.isEmpty)

        let works = context.ownedClips(from: [Submission(id: UUID(), title: "Practice rally")])
        let clip = try XCTUnwrap(works.first)
        try context.change(clip.id, kind: .like, enabled: true)
        try context.change(clip.id, kind: .save, enabled: true)
        let totals = context.state.receivedTotals(for: works)
        XCTAssertEqual(totals.likes, 0)
        XCTAssertEqual(totals.saves, 0)
        XCTAssertTrue(context.state.likes.contains(clip.id))
        XCTAssertTrue(context.state.saves.contains(clip.id))
    }

    func testBlockedChatsDisappearWithoutDeletingHistoryAndRestore() throws {
        let context = try makeContext()
        defer { context.wallet.stop() }
        let person = ChatPerson(id: "player:" + UUID().uuidString, name: "Nearby player")
        let other = ChatPerson(id: "player:" + UUID().uuidString, name: "Other player")
        for target in [person, other] {
            try context.library.addChatEntry(
                ChatEntry(id: UUID(), text: "Retained message", date: Date(), kind: .incoming), for: target)
        }
        XCTAssertEqual(try context.chat.histories().count, 2)
        try context.chat.setBlocked(person, enabled: true)
        try context.reloadState()
        XCTAssertEqual(try context.chat.histories().map(\.person.id), [other.id])
        XCTAssertTrue(try context.chat.history(for: person).isEmpty)
        XCTAssertEqual(try context.library.chatHistories().count, 2)
        XCTAssertNotNil(context.chat.restriction(for: person))
        XCTAssertEqual(try context.library.blockedPeople()[person.id]?.name, person.name)
        try context.chat.setBlocked(person, enabled: false)
        XCTAssertEqual(try context.chat.histories().count, 2)
        XCTAssertEqual(try context.chat.history(for: person).count, 1)
    }

    func testIndependentHideAndAccountIsolation() throws {
        let first = try makeContext()
        let second = try makeContext()
        defer {
            first.wallet.stop()
            second.wallet.stop()
        }
        let clip = try XCTUnwrap(first.catalog.shorts.first)
        try first.report(clip.id, reason: .other)
        try first.change(clip.id, kind: .hide, enabled: true)
        try first.cancelReport(clip.id)
        XCTAssertFalse(first.state.canShow(clip))
        XCTAssertTrue(second.state.canShow(clip))
        XCTAssertTrue(try second.library.safetyEvents().isEmpty)
        try first.change(clip.id, kind: .hide, enabled: false)
        XCTAssertTrue(first.state.canShow(clip))
    }

    func testInvalidSelfAndHiddenTargetsAreRejected() throws {
        let context = try makeContext()
        defer { context.wallet.stop() }
        XCTAssertThrowsError(try context.report("missing-content", reason: .other))
        XCTAssertThrowsError(
            try context.chat.setBlocked(
                ChatPerson(id: context.state.me.id.uuidString, name: "Me"), enabled: true))
        XCTAssertThrowsError(
            try context.chat.setBlocked(
                ChatPerson(id: "missing-person", name: "Unknown"), enabled: true))
        let clip = try XCTUnwrap(context.catalog.shorts.first)
        try context.report(clip.id, reason: .other)
        XCTAssertThrowsError(try context.report(clip.id, reason: .misleading))
        XCTAssertEqual(try context.library.safetyEvents().count, 1)
    }

    func testHiddenContentCannotReopenThroughDetailOrComments() throws {
        let context = try makeContext()
        defer { context.wallet.stop() }
        let course = try XCTUnwrap(context.catalog.courses.first)
        let clip = try XCTUnwrap(context.catalog.shorts.first)
        let openComments = DiscussionSheet(context, clip: clip, onChange: {}, onClose: {})
        openComments.loadViewIfNeeded()
        XCTAssertFalse(labels(in: openComments.view).contains("Comments unavailable"))
        try context.report(course.id, reason: .other)
        try context.report(clip.id, reason: .other)
        XCTAssertTrue(labels(in: openComments.view).contains("Comments unavailable"))
        let detail = CourseScreen(context, course: course)
        detail.loadViewIfNeeded()
        XCTAssertTrue(labels(in: detail.view).contains("This lesson is hidden from your lists."))
        let comments = DiscussionSheet(context, clip: clip, onChange: {}, onClose: {})
        comments.loadViewIfNeeded()
        XCTAssertTrue(labels(in: comments.view).contains("Comments unavailable"))
        let player = ShortsScreen(context, clips: [clip], selected: clip.id)
        player.loadViewIfNeeded()
        player.contentVisibilityDidChange()
        XCTAssertTrue(labels(in: player.view).contains("No clips available"))
    }

    func testFailedSaveKeepsVisibilityAndAuditUnchangedThenRetrySucceeds() throws {
        let context = try makeContext()
        defer { context.wallet.stop() }
        let clip = try XCTUnwrap(context.catalog.shorts.first)
        let files = FileManager.default
        let support = try files.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false)
        let index = support.appendingPathComponent("AccountLibraries")
            .appendingPathComponent(context.state.me.id.uuidString).appendingPathComponent("library.json")
        let backup = index.appendingPathExtension("backup")
        let original = try Data(contentsOf: index)
        try files.moveItem(at: index, to: backup)
        try files.createDirectory(at: index, withIntermediateDirectories: false)
        try Data("Blocked write".utf8).write(to: index.appendingPathComponent("obstacle"))
        defer {
            if files.fileExists(atPath: backup.path) {
                try? files.removeItem(at: index)
                try? files.moveItem(at: backup, to: index)
            }
        }
        XCTAssertThrowsError(try context.report(clip.id, reason: .other))
        XCTAssertThrowsError(try context.setBlocked(clip.author, enabled: true))
        XCTAssertTrue(context.state.canShow(clip))
        XCTAssertFalse(context.state.blocked.contains(clip.publisherID))
        XCTAssertTrue(try context.library.reportedContent().isEmpty)
        XCTAssertTrue(try context.library.safetyEvents().isEmpty)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        try files.removeItem(at: index)
        try files.moveItem(at: backup, to: index)
        try context.report(clip.id, reason: .other)
        XCTAssertFalse(context.state.canShow(clip))
        XCTAssertEqual(try context.library.safetyEvents().count, 1)
    }

    func testFailedUndoPreservesBothReasonsAndAuditUntilRetry() throws {
        let context = try makeContext()
        defer { context.wallet.stop() }
        let clip = try XCTUnwrap(context.catalog.shorts.first)
        try context.report(clip.id, reason: .other)
        try context.setBlocked(clip.author, enabled: true)
        let files = FileManager.default
        let support = try files.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let index = support.appendingPathComponent("AccountLibraries")
            .appendingPathComponent(context.state.me.id.uuidString).appendingPathComponent("library.json")
        let backup = index.appendingPathExtension("backup")
        try files.moveItem(at: index, to: backup)
        try files.createDirectory(at: index, withIntermediateDirectories: false)
        try Data("Blocked write".utf8).write(to: index.appendingPathComponent("obstacle"))
        defer {
            if files.fileExists(atPath: backup.path) {
                try? files.removeItem(at: index)
                try? files.moveItem(at: backup, to: index)
            }
        }
        XCTAssertThrowsError(try context.cancelReport(clip.id))
        XCTAssertThrowsError(try context.setBlocked(clip.author, enabled: false))
        XCTAssertNotNil(try context.library.reportedContent()[clip.id])
        XCTAssertTrue(context.state.blocked.contains(clip.publisherID))
        XCTAssertFalse(context.state.canShow(clip))
        XCTAssertEqual(try context.library.safetyEvents().count, 2)
        try files.removeItem(at: index)
        try files.moveItem(at: backup, to: index)
        try context.cancelReport(clip.id)
        try context.setBlocked(clip.author, enabled: false)
        XCTAssertTrue(context.state.canShow(clip))
        XCTAssertEqual(try context.library.safetyEvents().count, 4)
    }

    func testReportsRefreshLoadedScreensAndSurviveReload() throws {
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.vava.walletacceptance.") == true else {
            XCTFail("Content tests require an isolated application.")
            return
        }
        let account = UUID()
        let library = try LocalLibrary(account: account)
        let profile = try library.open(revision: "2026-11-13.2", accepted: true)
        let wallet = try Wallet(account: profile.id)
        defer { wallet.stop() }
        let catalog: Catalog = try XCTUnwrap(Bundle.main.decode("catalog"))
        let context = try AppContext(library: library, wallet: wallet, catalog: catalog)
        let course = try XCTUnwrap(catalog.courses.first { context.state.canShow($0) })
        let clip = try XCTUnwrap(catalog.shorts.first { context.state.canShow($0) })
        defer {
            try? context.cancelReport(course.id)
            try? context.cancelReport(clip.id)
        }

        let academy = AcademyScreen(context)
        let publisher = PublisherProfileScreen(context, publisher: course.author, openTutorials: true)
        let shorts = ShortsScreen(context, clips: [clip], selected: clip.id)
        let screens: [Screen] = [academy, publisher, shorts]
        for screen in screens { screen.loadViewIfNeeded() }
        academy.contentVisibilityDidChange()
        publisher.contentVisibilityDidChange()
        shorts.contentVisibilityDidChange()
        XCTAssertTrue(labels(in: academy.view).contains(course.title))
        XCTAssertTrue(labels(in: publisher.view).contains(course.title))
        XCTAssertTrue(labels(in: shorts.view).contains(clip.title))

        try context.report(course.id, reason: .other)
        try context.report(clip.id, reason: .other)
        // No lifecycle callback or manual refresh occurs after reporting.
        XCTAssertFalse(labels(in: academy.view).contains(course.title))
        XCTAssertFalse(labels(in: publisher.view).contains(course.title))
        XCTAssertFalse(labels(in: shorts.view).contains(clip.title))
        XCTAssertTrue(labels(in: shorts.view).contains("No clips available"))

        // Reports remain authoritative even if a separate hide flag is cleared.
        try library.change(course.id, kind: .hide, enabled: false)
        try library.change(clip.id, kind: .hide, enabled: false)
        let reopened = try LocalLibrary(account: account)
        XCTAssertFalse(try reopened.state().canShow(course))
        XCTAssertFalse(try reopened.state().canShow(clip))

        try context.cancelReport(course.id)
        try context.cancelReport(clip.id)
        XCTAssertTrue(labels(in: academy.view).contains(course.title))
        XCTAssertTrue(labels(in: publisher.view).contains(course.title))
        XCTAssertTrue(labels(in: shorts.view).contains(clip.title))
    }

    private func labels(in view: UIView) -> [String] {
        let own = (view as? UILabel)?.text.map { [$0] } ?? []
        return own + view.subviews.flatMap { labels(in: $0) }
    }
}
