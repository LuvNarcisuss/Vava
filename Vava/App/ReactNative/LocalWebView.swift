import CryptoKit
import React
import WebKit
import ZIPFoundation

@objc(VavaLocalWebViewManager) final class VavaLocalWebViewManager: RCTViewManager {
    override static func requiresMainQueueSetup() -> Bool { true }
    override func view() -> UIView! { VavaLocalWebView(frame: .zero) }

}

private final class WeakPageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: VavaLocalWebView?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

final class VavaLocalWebView: UIView, WKNavigationDelegate {
    @objc var onDelivered: RCTDirectEventBlock?
    private var latestDelivery = 0
    @objc var messages = "[]" {
        didSet {
            guard let data = messages.data(using: .utf8), let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
            for item in items {
                guard let id = item["id"] as? Int, id > latestDelivery, let body = item["body"] as? String else { continue }
                latestDelivery = id
                send(body, delivery: id)
            }
        }
    }
    @objc var onMessage: RCTDirectEventBlock?
    @objc var onFailure: RCTDirectEventBlock?
    private let page: WKWebView
    private let handler = WeakPageHandler()
    private let files = FileManager.default
    private let queue = DispatchQueue(label: "com.vava.local-page", qos: .userInitiated)
    private var root: URL?
    private var observers: [NSObjectProtocol] = []
    private var frameInFlight = false
    private var lastFrame = Date.distantPast
    private var account: String?
    private var revision: UInt64 = 0
    private var loaded = false
    private static let cacheDirectory: URL = {
        let files = FileManager.default
        let directory = files.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VavaPages", isDirectory: true)
        // A terminated process cannot release its views. Remove only its exported page copies.
        try? files.removeItem(at: directory)
        return directory
    }()

    override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(handler, name: "vava")
        page = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        handler.owner = self
        backgroundColor = UIColor(red: 13/255, green: 33/255, blue: 31/255, alpha: 1)
        page.isOpaque = false
        page.backgroundColor = backgroundColor
        page.scrollView.backgroundColor = backgroundColor
        page.scrollView.isScrollEnabled = false
        page.scrollView.contentInsetAdjustmentBehavior = .never
        page.navigationDelegate = self
        if #available(iOS 16.4, *) { page.isInspectable = _isDebugAssertConfiguration() }
        addSubview(page)
        observers.append(NotificationCenter.default.addObserver(forName: VavaNative.callFrame, object: nil, queue: .main) { [weak self] notification in
            guard let image = notification.object as? UIImage, let bytes = image.jpegData(compressionQuality: 0.65) else { return }
            self?.deliverCallFrame(bytes, event: "vava-call-frame")
        })
        observers.append(NotificationCenter.default.addObserver(forName: VavaNative.callPreviewFrame, object: nil, queue: .main) { [weak self] notification in
            guard let bytes = notification.object as? Data else { return }
            self?.deliverCallFrame(bytes, event: "vava-call-preview-frame")
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.page.evaluateJavaScript("document.querySelectorAll('video').forEach(video => video.pause())")
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.page.evaluateJavaScript("window.dispatchEvent(new Event('vava-playback'))")
        })
    }
    private func deliverCallFrame(_ bytes: Data, event: String) {
        guard !frameInFlight, Date().timeIntervalSince(lastFrame) >= 0.1 else { return }
        lastFrame = Date()
        frameInFlight = true
        page.callAsyncJavaScript(
            "window.dispatchEvent(new CustomEvent(event, { detail: frame }))",
            arguments: ["event": event, "frame": "data:image/jpeg;base64," + bytes.base64EncodedString()],
            in: nil, in: .page
        ) { [weak self] _ in self?.frameInFlight = false }
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() { super.layoutSubviews(); page.frame = bounds }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !loaded else { return }
        loaded = true
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let root = try self.prepare()
                DispatchQueue.main.async {
                    self.root = root
                    self.page.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
                }
            } catch { DispatchQueue.main.async { self.fail("Vava's pages could not be opened. Please try again.") } }
        }
    }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        page.configuration.userContentController.removeScriptMessageHandler(forName: "vava")
        if let root { try? files.removeItem(at: root) }
    }
    private func prepare() throws -> URL {
        guard let archiveURL = Bundle.main.url(forResource: "vava", withExtension: "zip") else { throw AppFailure("The page archive is missing.") }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        var total: UInt64 = 0
        for entry in archive {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard entry.type != .symlink, !entry.path.hasPrefix("/"), !components.contains(".."), !entry.path.contains("\\") else { throw AppFailure("The page archive is invalid.") }
            total += UInt64(entry.uncompressedSize)
            guard total < 50_000_000 else { throw AppFailure("The page archive is too large.") }
        }
        let cache = Self.cacheDirectory
        try files.createDirectory(at: cache, withIntermediateDirectories: true)
        // A per-view export directory never grants WebKit access to account or wallet files.
        let destination = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try files.unzipItem(at: archiveURL, to: destination)
            guard files.fileExists(atPath: destination.appendingPathComponent("index.html").path) else { throw AppFailure("The page entry is missing.") }
            try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            return destination
        } catch { try? files.removeItem(at: destination); throw error }
    }
    func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let root, let url = message.frameInfo.request.url,
              url.isFileURL, url.standardizedFileURL == root.appendingPathComponent("index.html").standardizedFileURL,
              let value = message.body as? [String: Any], JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value), data.count < 2_000_000,
              let body = String(data: data, encoding: .utf8) else { return }
        onMessage?(["body": body])
    }
    private func send(_ message: String, delivery: Int) {
        guard let root, let data = message.data(using: .utf8) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let value = try JSONSerialization.jsonObject(with: data)
                if let object = value as? [String: Any] {
                    let snapshot = object["snapshot"] as? [String: Any] ?? (object["result"] as? [String: Any])?["snapshot"] as? [String: Any]
                    if let snapshot, let incoming = snapshot["revision"] as? UInt64, incoming >= self.revision {
                        self.revision = incoming
                        let state = snapshot["state"] as? [String: Any]
                        let next = (state?["me"] as? [String: Any])?["id"] as? String
                        if next != self.account {
                            let media = root.appendingPathComponent("media", isDirectory: true)
                            if self.files.fileExists(atPath: media.path) { try self.files.removeItem(at: media) }
                            self.account = next
                        }
                    }
                }
                let exported = try self.export(value, root: root)
                DispatchQueue.main.async {
                    self.page.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('vava-native', {detail: message}))", arguments: ["message": exported], in: nil, in: .page) { [weak self] result in
                        switch result {
                        case .success: self?.onDelivered?(["id": delivery])
                        case .failure: self?.fail("The page stopped responding. Please try again.")
                        }
                    }
                }
            } catch { DispatchQueue.main.async { self.fail("Vava could not load this page's media. Please try again.") } }
        }
    }
    private func export(_ value: Any, root: URL) throws -> Any {
        if let object = value as? [String: Any] {
            return try object.reduce(into: [String: Any]()) { result, entry in
                if ["media", "cover", "avatar", "avatarURI"].contains(entry.key), let text = entry.value as? String, text.hasPrefix("file:") {
                    result[entry.key] = try exportMedia(text, root: root)
                } else { result[entry.key] = try export(entry.value, root: root) }
            }
        }
        if let array = value as? [Any] { return try array.map { try export($0, root: root) } }
        return value
    }
    private func exportMedia(_ text: String, root: URL) throws -> String {
        guard let url = URL(string: text), url.isFileURL else { return text }
        let original = url.resolvingSymlinksInPath().standardizedFileURL
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().path + "/"
        let imports = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalLibrary/Videos").resolvingSymlinksInPath().path + "/"
        let ext = original.pathExtension.lowercased()
        guard (original.path.hasPrefix(bundle) || original.path.hasPrefix(imports)), ["png", "jpg", "jpeg", "mp4", "mov", "m4v"].contains(ext) else { throw AppFailure("This media cannot be opened.") }
        let attributes = try files.attributesOfItem(atPath: original.path)
        let signature = original.absoluteString + String(describing: attributes[.modificationDate]) + String(describing: attributes[.size])
        let name = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined() + "." + ext
        let directory = root.appendingPathComponent("media", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        if !files.fileExists(atPath: destination.path) { try files.copyItem(at: original, to: destination) }
        return destination.absoluteString
    }
    private func fail(_ message: String) { onFailure?(["message": message]) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = action.targetFrame?.isMainFrame == true && action.request.url?.standardizedFileURL == root?.appendingPathComponent("index.html").standardizedFileURL
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("Vava's pages could not be opened. Please try again.") }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("Vava's pages could not be opened. Please try again.") }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("The page was interrupted. Please try again.") }
}
