import StoreKit
import StoreKitTest
import WebKit
import XCTest
@testable import Vava

@MainActor final class LocalH5Tests: XCTestCase {
    private var page: WKWebView!
    private func findPage(_ view: UIView) -> WKWebView? {
        if let page = view as? WKWebView { return page }
        return view.subviews.lazy.compactMap { self.findPage($0) }.first
    }
    private func js(_ source: String) async throws -> Any? { try await page.evaluateJavaScript(source) }
    private func literal(_ value: String) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed), encoding: .utf8)!
    }
    private func wait(_ predicate: String, timeout: TimeInterval = 20) async throws {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if (try? await js(predicate)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "H5Acceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out: \(predicate). Page: \((try? await js("document.body.innerText")) ?? "unavailable")"])
    }
    private func text(_ value: String) async throws {
        try await wait("document.body.innerText.includes(\(literal(value)))")
    }
    private func tap(_ label: String, prefix: Bool = false) async throws {
        let value = try literal(label)
        let selector = "Array.from((document.querySelector('dialog[open]') || document).querySelectorAll('[role=button],[role=tab],[role=checkbox],button,a')).find(e => e.getClientRects().length && [(e.getAttribute('aria-label') || ''), e.innerText.trim()].some(s => \(prefix ? "s.startsWith(\(value))" : "s === \(value)")))"
        try await wait("!!(\(selector))")
        _ = try await js("(\(selector)).click(); true")
        try await Task.sleep(nanoseconds: 250_000_000)
    }
    private func input(_ label: String, value: String) async throws {
        let selector = try "Array.from(document.querySelectorAll('input,textarea')).find(e => e.getAttribute('aria-label') === \(literal(label)))"
        _ = try await js("(() => { const e = \(selector); if (!e) throw new Error('Missing input'); const setter = Object.getOwnPropertyDescriptor(e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, 'value').set; setter.call(e, \(literal(value))); e.dispatchEvent(new Event('input', {bubbles:true})); return true; })()")
    }
    private func capture(_ name: String) async throws {
        let image = try await page.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        print("H5_ACCEPTANCE page=\(name)")
    }
    private func expectPageBackground(_ visible: Bool = true) async throws {
        try await wait("""
        (() => {
          const background = document.querySelector('[data-testid="vava-screen-background"]');
          if (!\(visible)) return !background;
          const image = background?.querySelector('img');
          return !!image && image.src.endsWith('/art/background.png') && image.complete && image.naturalWidth > 0 &&
            background.getBoundingClientRect().width >= document.documentElement.clientWidth - 1;
        })()
        """)
    }
    private func logIn() async throws {
        try await wait("""
        (() => {
          const consent = document.querySelector('[aria-label="Accept the agreements"]');
          const button = Array.from(document.querySelectorAll('[role="button"],button'))
            .find(element => element.innerText.trim() === 'Log in');
          const links = Array.from(document.querySelectorAll('[role="link"],a'));
          return consent?.getAttribute('aria-checked') === 'false' &&
            (button?.disabled || button?.getAttribute('aria-disabled') === 'true') &&
            ['Terms of Service', 'Privacy Policy'].every(title => links.some(link => link.innerText.trim() === title));
        })()
        """)
        try await expectPageBackground()
        try await wait("document.querySelector('[aria-label=\"Vava logo\"]').getBoundingClientRect().width <= 145")
        try await capture("Login with unchecked agreement")
        try await tap("Accept the agreements")
        try await wait("document.querySelector('[aria-label=\"Accept the agreements\"]')?.getAttribute('aria-checked') === 'true'")
        try await tap("Log in")
    }
    func testLocalPagesAndNativeWallet() async throws {
        continueAfterFailure = false
        let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertTrue(bundle.hasPrefix("com.vava.h5acceptance."))
        guard bundle.hasPrefix("com.vava.h5acceptance.") else { return }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VavaCoins", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState(); session.disableDialogs = true
        defer { session.resetToDefaultState() }
        let end = Date().addingTimeInterval(40)
        while page == nil && Date() < end {
            page = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).compactMap { self.findPage($0) }.first
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNotNil(page)
        try await wait("!!document.querySelector('[aria-label=\"Accept the agreements\"]')")
        // Seed an existing local profile before bootstrap to exercise returning entry.
        let returning = try LocalLibrary().open(revision: "2026-11-13.2", accepted: true)
        _ = try await js("location.reload(); true")
        try await logIn()
        try await text("Find your ready position")
        XCTAssertEqual(try LocalLibrary().state().me.id, returning.id)
        XCTAssertTrue(page.url?.isFileURL == true)
        XCTAssertTrue(page.url?.lastPathComponent == "index.html")
        try await expectPageBackground()
        try await capture("Academy")
        try await wait("Array.from(document.images).filter(i => i.src && i.getClientRects().length).every(i => i.complete && i.naturalWidth > 0)")
        try await tap("Find your ready position", prefix: true)
        try await text("Save lesson")
        try await tap("Save lesson")
        try await text("Remove from saved")
        try await capture("Course detail")
        try await tap("Back")
        try await tap("View Tom Lodziak profile")
        let profileActionsAreAligned = try await js("""
        (() => {
          const buttons = Array.from(document.querySelectorAll('[role=button],button'));
          const find = label => buttons.find(button => button.getClientRects().length &&
            (button.getAttribute('aria-label') === label || button.innerText.trim() === label));
          const block = find('Block');
          const frames = [find('Follow'), find('Message'), block].map(button => button?.getBoundingClientRect());
          const [follow, message, icon] = frames;
          return frames.every(Boolean) && block.innerText.trim() === '🚫' &&
            Math.abs(follow.width - message.width) < 1 && icon.width < follow.width &&
            frames.every(frame => Math.abs(frame.top - follow.top) < 1 && Math.abs(frame.height - follow.height) < 1);
        })()
        """) as? Bool
        XCTAssertEqual(profileActionsAreAligned, true)
        try await capture("Publisher")
        try await tap("Follow")
        try await tap("Message")
        try await wait("!!document.querySelector('[aria-label=\"Voice call\"]')")
        try await expectPageBackground()
        try await capture("Conversation")
        try await tap("Back")
        try await tap("Back")
        try await tap("Watch")
        try await text("Sun Yingsha vs Wang Manyu")
        try await expectPageBackground()
        try await capture("Watch")
        let hasRefreshButton = try await js("""
        Array.from(document.querySelectorAll('[role=button],button')).some(button =>
          button.getClientRects().length &&
          (button.getAttribute('aria-label') === 'Refresh' || button.innerText.trim() === 'Refresh'))
        """) as? Bool
        XCTAssertEqual(hasRefreshButton, false)
        _ = try await js("""
        (() => {
          const card = document.querySelector('[aria-label="Sun Yingsha vs Wang Manyu"]');
          const make = y => new Touch({identifier: 1, target: card, clientX: 160, clientY: y});
          const start = make(260), end = make(420);
          card.dispatchEvent(new TouchEvent('touchstart', {bubbles: true, touches: [start], changedTouches: [start]}));
          card.dispatchEvent(new TouchEvent('touchend', {bubbles: true, touches: [], changedTouches: [end]}));
          return true;
        })()
        """)
        try await text("Updated")
        try await tap("Sun Yingsha vs Wang Manyu")
        try await tap("Save replay")
        try await text("Remove from saved")
        try await capture("Replay detail")
        try await tap("Back")
        try await tap("Shorts")
        try await text("Ravne league final")
        try await wait("document.querySelector('video').readyState >= 2", timeout: 40)
        try await expectPageBackground(false)
        let shortsLayoutMatches = try await js("""
        (() => {
          const video = document.querySelector('video');
          const player = document.querySelector('[aria-label="Pause video"]');
          const caption = document.querySelector('[data-testid="shorts-caption"]');
          const actions = document.querySelector('[data-testid="shorts-actions"]');
          const progress = document.querySelector('[aria-label="Video progress"]');
          const dock = document.querySelector('[role="tablist"]');
          if (![video, player, caption, actions, progress, dock].every(Boolean)) return false;
          const [media, surface, left, right, track, tabs] = [video, player, caption, actions, progress, dock]
            .map(node => node.getBoundingClientRect());
          return getComputedStyle(video).objectFit === 'contain' &&
            Math.abs(media.width - surface.width) < 1 && Math.abs(media.height - surface.height) < 1 &&
            left.right < right.left && Math.abs(left.bottom - right.bottom) < 1 &&
            track.left <= left.left && track.right >= right.right && track.top >= right.bottom &&
            track.bottom <= tabs.top;
        })()
        """) as? Bool
        XCTAssertEqual(shortsLayoutMatches, true)
        try await capture("Shorts")
        _ = try await js("""
        (() => {
          const e = document.querySelector('[aria-label="Pause video"]');
          const make = y => new Touch({identifier: 1, target: e, clientX: 160, clientY: y, pageX: 160, pageY: y, screenX: 160, screenY: y});
          const start = make(500), moved = make(320);
          e.dispatchEvent(new TouchEvent('touchstart', {bubbles: true, touches: [start], changedTouches: [start]}));
          e.dispatchEvent(new TouchEvent('touchmove', {bubbles: true, touches: [moved], changedTouches: [moved]}));
          return true;
        })()
        """)
        try await wait("""
        (() => {
          const pages = document.querySelector('[data-testid="shorts-video-pages"]');
          const transform = getComputedStyle(pages).transform;
          return transform !== 'none' && new DOMMatrix(transform).m42 < -60 &&
            document.querySelector('[data-testid="shorts-caption"]').innerText.includes('Ravne league final');
        })()
        """)
        try await capture("Shorts during drag")
        _ = try await js("""
        (() => {
          const e = document.querySelector('[aria-label="Pause video"]');
          const end = new Touch({identifier: 1, target: e, clientX: 160, clientY: 180, pageX: 160, pageY: 180});
          e.dispatchEvent(new TouchEvent('touchend', {bubbles: true, touches: [], changedTouches: [end]}));
          return true;
        })()
        """)
        try await text("Netherlands vs China")
        _ = try await js("""
        (() => {
          const e = document.querySelector('[aria-label="Pause video"]');
          const make = y => new Touch({identifier: 2, target: e, clientX: 160, clientY: y, pageX: 160, pageY: y, screenX: 160, screenY: y});
          const start = make(180), end = make(500);
          e.dispatchEvent(new TouchEvent('touchstart', {bubbles: true, touches: [start], changedTouches: [start]}));
          e.dispatchEvent(new TouchEvent('touchend', {bubbles: true, touches: [], changedTouches: [end]}));
          return true;
        })()
        """)
        try await text("Ravne league final")
        try await tap("Like clip,", prefix: true)
        try await tap("Comments,", prefix: true)
        try await input("Add a private comment", value: "A private H5 acceptance note.")
        try await tap("Save")
        try await text("A private H5 acceptance note.")
        try await capture("Comments")
        try await tap("Close comments")
        try await tap("More clip actions")
        try await tap("Source and license")
        try await capture("Clip source")
        try await tap("Back")
        try await tap("Add a video")
        try await text("Choose and save video")
        try await expectPageBackground()
        try await capture("Import")
        try await tap("Back")
        try await tap("Chats")
        try await expectPageBackground()
        try await capture("Chats")
        try await tap("Find players")
        try await capture("Discovery")
        try await tap("Back")
        try await tap("Me")
        try await expectPageBackground()
        try await capture("Me")
        try await tap("Wallet ·", prefix: true)
        try await wait("Array.from(document.querySelectorAll('[aria-label]')).some(e => e.getAttribute('aria-label').startsWith('400 coins,') && !e.getAttribute('aria-label').includes('Unavailable'))")
        try await expectPageBackground()
        try await capture("Wallet")
        try await tap("400 coins,", prefix: true)
        try await tap("Buy ·", prefix: true)
        try await text("Coins added to your wallet.")
        try await tap("OK")
        try await text("400 coins")
        let library = try LocalLibrary()
        let profile = try library.state().me
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let ledgerURL = support.appendingPathComponent("LocalStoreKitWallets/\(profile.id.uuidString).json")
        let credited = try Data(contentsOf: ledgerURL)
        XCTAssertEqual(try JSONDecoder().decode(WalletLedger.self, from: credited).balance, 400)
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: StoreKitPurchaseAPI())
        try await tap("Buy ·", prefix: true)
        try await text("Purchase canceled.")
        try await tap("OK")
        XCTAssertEqual(try Data(contentsOf: ledgerURL), credited)
        try await session.setSimulatedError(nil, forAPI: StoreKitPurchaseAPI())
        let latest = await Transaction.latest(for: "ampqtftkneoumheh")
        let verified = try XCTUnwrap(latest)
        guard case .verified(let transaction) = verified else { XCTFail("Expected verified StoreKit transaction"); return }
        XCTAssertEqual(transaction.appAccountToken, profile.id)
        let duplicateReceiver = try Wallet(account: profile.id)
        for _ in 0..<12 { await duplicateReceiver.receive(verified) }
        duplicateReceiver.stop()
        XCTAssertEqual(try Data(contentsOf: ledgerURL), credited)
        try await capture("Wallet credited")
        try await tap("Back")
        try await text("Wallet · 400 coins")
        try await tap("Settings")
        try await expectPageBackground()
        try await capture("Settings")
        try await tap("Edit profile")
        try await input("Display name", value: "H5 Acceptance")
        try await tap("Save profile")
        try await tap("Blocked publishers")
        try await capture("Blocked publishers")
        try await tap("Back")
        try await tap("Media credits")
        try await capture("Media credits")
        try await tap("Ravne league final", prefix: true)
        try await capture("Source credit")
        try await tap("Back")
        try await tap("Back")
        try await tap("Back")
        try await text("H5 Acceptance")
        XCTAssertEqual(try Data(contentsOf: ledgerURL), credited)
        try await tap("Settings")
        try await tap("Log out")
        try await tap("Log out")
        try await logIn()
        try await text("Find your ready position")
        try await tap("Me")
        try await text("H5 Acceptance")
        try await text("Wallet · 400 coins")
        _ = try await js("location.reload(); true")
        try await text("Find your ready position")
        try await tap("Me")
        try await text("Wallet · 400 coins")
        try await capture("Restored profile")
        XCTAssertEqual(try Data(contentsOf: ledgerURL), credited)
        print("H5_ACCEPTANCE local_entry=true success_balance=400 cancellation_unchanged=true duplicate_callbacks=12 relogin=true reload=true")
    }
}
