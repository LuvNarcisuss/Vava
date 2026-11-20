import Foundation
import React
import UIKit

@objc(VavaNative) @MainActor final class VavaNative: RCTEventEmitter {
    static weak var shared: VavaNative?
    static let callFrame = Notification.Name("Vava.ReactNative.CallFrame")
    static let callPreviewFrame = Notification.Name("Vava.ReactNative.CallPreviewFrame")
    private var library: LocalLibrary?
    private var wallet: Wallet?
    private var chat: ChatService?
    private var callPreview: LocalCallPreview?
    private var catalog: Catalog?
    private var knownPeople: [String: ChatPerson] = [:]
    private var snapshotRevision: UInt64 = 0
    private var invalidated = false
    private var signedIn = false
    private var listening = false
    private var observers: [NSObjectProtocol] = []
    private let media = NativeMediaActions()
    private let revision = "2026-11-13.2"
    private let terms = "https://docs.google.com/document/d/1HKDBNvyA7Vha5_sVVoc4P4Z8e-udZkrMlfdbTgVvdOs"
    private let privacy = "https://docs.google.com/document/d/1_ldTUi2Y1bfT5x9BphLfDo3AwM7ZBpNxUnHFmwI2GFo"

    override init() {
        super.init()
        Self.shared = self
        for name in [Notification.Name.walletChanged, ChatService.changed] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in Task { @MainActor in self?.publish() }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    override static func requiresMainQueueSetup() -> Bool { true }
    override func supportedEvents() -> [String]! { ["stateChanged"] }
    override func startObserving() {
        Task { @MainActor [weak self] in
            guard let self, !self.invalidated else { return }
            self.listening = true
        }
    }
    override func stopObserving() {
        Task { @MainActor [weak self] in self?.listening = false }
    }
    override func invalidate() {
        Task { @MainActor in
            self.invalidated = true
            self.listening = false
            self.media.invalidate()
            self.leave()
            self.observers.forEach(NotificationCenter.default.removeObserver)
            self.observers.removeAll()
            self.catalog = nil
            self.library = nil
            if Self.shared === self { Self.shared = nil }
        }
        super.invalidate()
    }
    func suspend() {
        stopCallPreview()
        chat?.suspend()
    }
    func resume() { chat?.resume() }

    @objc(request:payload:resolver:rejecter:)
    func request(_ command: String, payload: NSDictionary,
                 resolver resolve: @escaping RCTPromiseResolveBlock,
                 rejecter reject: @escaping RCTPromiseRejectBlock) {
        Task { @MainActor in
            do {
                guard !invalidated else { throw CancellationError() }
                if command == "pickAvatar" {
                    guard signedIn, let library else { throw AppFailure("Log in to continue.") }
                    let account = try library.state().me.id
                    let avatar = try await media.pickAvatar()
                    try ensureAccount(account)
                    var result: [String: Any] = ["snapshot": try snapshot()]
                    if let avatar { result["avatarURI"] = "data:image/jpeg;base64," + avatar.base64EncodedString() }
                    resolve(result)
                    return
                }
                let message = try await execute(command, payload: payload)
                var result: [String: Any] = ["snapshot": try snapshot()]
                if let message { result["message"] = message }
                resolve(result)
                publish()
            } catch {
                publish()
                reject("VAVA_OPERATION_FAILED", error.localizedDescription, error)
            }
        }
    }

    private func openLibrary() throws -> LocalLibrary {
        if let library { return library }
        let opened = try LocalLibrary()
        library = opened
        return opened
    }

    private func enter() throws {
        guard !signedIn else { return }
        let library = try openLibrary()
        try library.finishPendingDeletion()
        let needsConsent = try !library.hasAccepted(revision)
        let profile = try library.open(revision: revision, accepted: needsConsent)
        guard let catalog: Catalog = Bundle.main.decode("catalog") else {
            throw AppFailure("Videos and lessons could not be loaded.")
        }
        let wallet = try Wallet(account: profile.id)
        let chat = ChatService(library: library)
        chat.showIncomingCall = { [weak self] _ in self?.signedIn == true }
        chat.onVideoFrame = { frame in
            NotificationCenter.default.post(name: Self.callFrame, object: frame)
        }
        self.catalog = catalog
        self.wallet = wallet
        self.chat = chat
        signedIn = true
        if chat.hasIdentity { try? chat.start() }
    }

    private func leave() {
        signedIn = false
        stopCallPreview()
        chat?.stop()
        wallet?.stop()
        chat = nil
        wallet = nil
        knownPeople.removeAll()
    }

    private func execute(_ command: String, payload: NSDictionary) async throws -> String? {
        let library = try openLibrary()
        if command == "bootstrap" {
            stopCallPreview()
            try library.reload()
            try library.finishPendingDeletion()
            return nil
        }
        if command == "login" {
            guard payload["accepted"] as? Bool == true else {
                throw AppFailure("Accept the agreements to continue.")
            }
            try enter()
            return nil
        }
        if command == "openURL" {
            try media.openURL(try string("url", in: payload))
            return nil
        }
        if command == "refresh", !signedIn {
            try library.reload()
            try library.finishPendingDeletion()
            return nil
        }
        guard signedIn, let wallet, let chat, let catalog else {
            throw AppFailure("Log in to continue.")
        }
        let account = try library.state().me.id
        switch command {
        case "refresh":
            try library.reload()
            if chat.hasIdentity { try chat.start() }
        case "signOut":
            try library.signOut()
            leave()
        case "deleteAccount":
            try library.beginAccountDeletion()
            leave()
            try library.finishPendingDeletion()
        case "activity":
            let id = try string("id", in: payload)
            let kind: Activity
            switch try string("kind", in: payload) {
            case "like": kind = .like
            case "save": kind = .save
            case "hide": kind = .hide
            default: throw AppFailure("This action is unavailable.")
            }
            try library.change(id, kind: kind, enabled: payload["enabled"] as? Bool == true)
        case "report":
            let id = try string("id", in: payload)
            guard catalog.shorts.contains(where: { $0.id == id }) || catalog.courses.contains(where: { $0.id == id }),
                  let reason = ReportReason(rawValue: try string("reason", in: payload)) else {
                throw AppFailure("This content is unavailable.")
            }
            try library.report(id, reason: reason)
        case "follow":
            try library.setFollowing(try string("id", in: payload), enabled: payload["enabled"] as? Bool == true)
        case "block":
            try chat.setBlocked(person(try string("id", in: payload)), enabled: payload["enabled"] as? Bool == true)
        case "practice":
            let course = try course(try string("id", in: payload))
            guard let step = payload["step"] as? Int, (course.steps ?? []).indices.contains(step),
                  course.price == 0 || wallet.ledger.owned.contains(course.id) else {
                throw AppFailure("Unlock this practice plan to continue.")
            }
            try library.markPractice(course: course.id, step: step, completed: payload["completed"] as? Bool == true)
        case "unlock": try wallet.unlock(course(try string("id", in: payload)))
        case "editProfile":
            let name = try string("name", in: payload).trimmed
            let bio = (payload["bio"] as? String ?? "").trimmed
            guard (1...40).contains(name.count), bio.count <= 180 else {
                throw AppFailure("Use 1–40 characters for your name and up to 180 for your biography.")
            }
            var avatar = try library.state().me.avatarJPEG
            if let uri = payload["avatarURI"] as? String {
                let prefix = "data:image/jpeg;base64,"
                guard uri.hasPrefix(prefix),
                      let data = Data(base64Encoded: String(uri.dropFirst(prefix.count))),
                      data.count <= 1_000_000, UIImage(data: data) != nil else {
                    throw AppFailure("This photo could not be saved.")
                }
                avatar = data
            }
            try library.editProfile(name: name, bio: bio, avatarJPEG: avatar)
        case "importVideo":
            let title = try string("title", in: payload).trimmed
            guard (1...80).contains(title.count), payload["accepted"] as? Bool == true else {
                throw AppFailure("Add a title and confirm permission to use this video.")
            }
            if let file = try await media.pickVideo() {
                defer { try? FileManager.default.removeItem(at: file) }
                try ensureAccount(account)
                try library.addVideo(from: file, id: UUID(), title: title)
                return "Video saved."
            }
        case "removeVideo":
            let id = try string("id", in: payload)
            guard let video = try library.submissions().first(where: { $0.id.uuidString == id }) else {
                throw AppFailure("This video is unavailable.")
            }
            try library.removeVideo(video)
        case "comment":
            let clipID = try string("clip", in: payload)
            let body = try string("body", in: payload).trimmed
            guard (1...200).contains(body.count) else { throw AppFailure("Use 1–200 characters.") }
            let state = try library.state()
            let local = state.commentsByClip[clipID] ?? []
            let clip = catalog.shorts.first { $0.id == clipID }
            let isOwnedClip = try library.submissions().contains(where: { $0.id.uuidString == clipID })
            guard clip != nil || isOwnedClip else {
                throw AppFailure("This video is unavailable.")
            }
            let reply = (payload["replyTo"] as? String).flatMap(UUID.init(uuidString:))
            if let reply, !local.contains(where: { $0.id == reply }),
               !(clip?.editorialComments.contains(where: { $0.id == reply }) ?? false) {
                throw AppFailure("This comment is unavailable.")
            }
            try library.post(clip: clipID, id: UUID(), body: body, replyTo: reply)
        case "share":
            let id = payload["id"] as? String
            var items: [Any] = []
            if let url = payload["url"] as? String, let parsed = URL(string: url) { items.append(parsed) }
            if let text = payload["text"] as? String { items.append(text) }
            if items.isEmpty, let id {
                if let clip = catalog.shorts.first(where: { $0.id == id }) {
                    if let source = clip.source { items.append(source) }
                    else { items.append(try assetURL(clip.media)) }
                } else if let uuid = UUID(uuidString: id) { items.append(try library.submissionURL(uuid)) }
            }
            if try await media.share(items), let id {
                try ensureAccount(account)
                try library.recordShare(id)
            }
        case "walletRefresh":
            await wallet.retryPendingPurchases()
            try await wallet.refresh()
        case "retryPurchases": await wallet.retryPendingPurchases()
        case "buy":
            let id = try string("productID", in: payload)
            guard let pack = CoinPack.all.first(where: { $0.productID == id }) else {
                throw AppFailure("This coin pack is unavailable.")
            }
            return try await wallet.buy(pack, price: string("price", in: payload))
        case "chatStart": try chat.start()
        case "chatOpen":
            let person = try person(string("id", in: payload))
            try chat.openConversation(person)
            if let restriction = chat.restriction(for: person) { try chat.recordNotice(restriction, for: person) }
        case "chatClose": chat.closeConversation(try person(string("id", in: payload)))
        case "chatHide": try chat.hideConversation(person(string("id", in: payload)))
        case "chatInbox":
            try chat.updateInbox(person(string("id", in: payload))) {
                if let pinned = payload["pinned"] as? Bool { $0.pinned = pinned }
                if let unread = payload["unread"] as? Bool { $0.unread = unread }
            }
        case "chatFollow":
            try chat.setFollowing(person(string("id", in: payload)), enabled: payload["enabled"] as? Bool == true)
        case "chatBlock":
            try chat.setBlocked(person(string("id", in: payload)), enabled: payload["enabled"] as? Bool == true)
        case "chatSend":
            return try chat.send(string("text", in: payload), to: person(string("id", in: payload)),
                                 retry: (payload["retryID"] as? String).flatMap(UUID.init(uuidString:)))
        case "chatCall":
            stopCallPreview()
            connectVideoFrames(chat)
            return try chat.requestCall(to: person(string("id", in: payload)), video: payload["video"] as? Bool == true)
        case "callAnswer":
            stopCallPreview()
            connectVideoFrames(chat)
            chat.answer(try identifier("id", in: payload))
        case "callEnd": chat.closeCall(try identifier("id", in: payload))
        case "callMute": chat.setMuted(payload["muted"] as? Bool == true)
        case "callPreviewStart":
            guard chat.call == nil else { throw AppFailure("Close the current call first.") }
            stopCallPreview()
            let preview = LocalCallPreview()
            callPreview = preview
            return try await preview.start(video: payload["video"] as? Bool == true) { frame in
                NotificationCenter.default.post(name: Self.callPreviewFrame, object: frame)
            }
        case "callPreviewStop": stopCallPreview()
        default: throw AppFailure("This action is unavailable.")
        }
        return nil
    }

    private func stopCallPreview() {
        callPreview?.stop()
        callPreview = nil
    }

    private func connectVideoFrames(_ chat: ChatService) {
        chat.onVideoFrame = { frame in
            NotificationCenter.default.post(name: Self.callFrame, object: frame)
        }
    }

    private func ensureAccount(_ account: UUID) throws {
        guard signedIn, try library?.state().me.id == account else {
            throw AppFailure("Your account changed. Please try again.")
        }
    }
    private func string(_ key: String, in payload: NSDictionary) throws -> String {
        guard let value = payload[key] as? String else { throw AppFailure("Required information is missing.") }
        return value
    }
    private func identifier(_ key: String, in payload: NSDictionary) throws -> UUID {
        guard let id = UUID(uuidString: try string(key, in: payload)) else { throw AppFailure("This item is unavailable.") }
        return id
    }
    private func course(_ id: String) throws -> Course {
        guard let course = catalog?.courses.first(where: { $0.id == id }) else {
            throw AppFailure("This course is unavailable.")
        }
        return course
    }
    private func person(_ id: String) throws -> ChatPerson {
        if let player = chat?.players.first(where: { $0.id == id }) { return player }
        if let person = knownPeople[id] { return person }
        if let person = try library?.chatHistories().first(where: { $0.person.id == id })?.person { return person }
        if let publisher = catalog?.courses.map(\.author).first(where: { $0.id == id }) { return ChatPerson(publisher) }
        if let clip = catalog?.shorts.first(where: { $0.publisherID == id }) { return ChatPerson(clip.author) }
        // Blocked nearby players may be offline and have no message history.
        if try library?.state().blocked.contains(id) == true { return ChatPerson(id: id, name: "Player") }
        throw AppFailure("This player is unavailable.")
    }
    private func assetURL(_ path: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "Media") else {
            throw AppFailure("This media is unavailable.")
        }
        return url
    }
    private func json<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
    private func profile(_ player: Player) -> [String: Any] {
        var value: [String: Any] = ["id": player.id.uuidString, "name": player.name, "bio": player.bio]
        if let avatar = player.avatarJPEG { value["avatarURI"] = "data:image/jpeg;base64," + avatar.base64EncodedString() }
        return value
    }
    private func personJSON(_ person: ChatPerson) -> [String: Any] {
        var value: [String: Any] = ["id": person.id, "name": person.name, "isPublisher": person.isPublisher,
                                  "code": person.code, "following": chat?.isFollowing(person) == true,
                                  "blocked": chat?.isBlocked(person) == true]
        if let restriction = chat?.restriction(for: person) { value["restriction"] = restriction }
        return value
    }
    private func snapshot() throws -> [String: Any] {
        guard !invalidated else { throw CancellationError() }
        let library = try openLibrary()
        snapshotRevision += 1
        var result: [String: Any] = [
            "revision": snapshotRevision,
            "signedIn": signedIn,
            "agreements": ["revision": revision, "terms": terms, "privacy": privacy],
            "catalog": ["shorts": [], "courses": [], "replays": []], "ownedClips": [],
            "chat": ["players": [], "histories": []]
        ]
        guard signedIn, let catalog, let wallet, let chat else { return result }
        let state = try library.state()
        for person in chat.players { knownPeople[person.id] = person }
        var catalogJSON = try json(catalog) as! [String: Any]
        for collection in ["shorts", "courses", "replays"] {
            var entries = catalogJSON[collection] as! [[String: Any]]
            for index in entries.indices {
                for key in ["media", "cover"] {
                    if let path = entries[index][key] as? String { entries[index][key] = try assetURL(path).absoluteString }
                }
                if var author = entries[index]["author"] as? [String: Any], let path = author["avatar"] as? String {
                    author["avatar"] = try assetURL(path).absoluteString
                    entries[index]["author"] = author
                }
            }
            catalogJSON[collection] = entries
        }
        result["catalog"] = catalogJSON
        var comments: [String: [[String: Any]]] = [:]
        for (clip, entries) in state.commentsByClip {
            comments[clip] = try entries.map { entry in
                var value = try json(entry) as! [String: Any]
                value["author"] = profile(entry.author)
                return value
            }
        }
        result["state"] = ["me": profile(state.me), "likes": Array(state.likes), "saves": Array(state.saves),
                           "hidden": Array(state.hidden), "practice": state.practice.mapValues(Array.init),
                           "following": Array(state.following), "blocked": Array(state.blocked),
                           "commentsByClip": comments, "shareCounts": state.shareCounts]
        result["ownedClips"] = try library.submissions().map { video -> [String: Any] in
            ["id": video.id.uuidString, "submissionID": video.id.uuidString, "title": video.title,
             "detail": "From your works.", "publisher": state.me.name, "publisherID": state.me.id.uuidString,
             "license": "", "media": (try? library.submissionURL(video.id).absoluteString) ?? "", "cover": "",
             "duration": 0, "engagement": ["likes": 0, "saves": 0, "shares": 0], "editorialComments": []]
        }
        result["wallet"] = ["balance": wallet.ledger.balance, "owned": Array(wallet.ledger.owned),
                            "entries": try json(wallet.ledger.entries), "busy": wallet.busy,
                            "retrying": wallet.retryingPurchases, "hasPurchaseIssue": wallet.hasPurchaseIssue,
                            "paymentsAllowed": wallet.paymentsAllowed,
                            "catalogStatus": wallet.catalogStatus.rawValue,
                            "catalogMessage": wallet.catalogMessage,
                            "packs": CoinPack.all.map { pack -> [String: Any] in
                                var value: [String: Any] = ["productID": pack.productID, "coins": pack.coins]
                                if let price = wallet.price(for: pack) { value["price"] = price }
                                return value
                            }]
        let histories = try library.chatHistories().sorted {
            let pinned = $0.inbox?.pinned == true
            if pinned != ($1.inbox?.pinned == true) { return pinned }
            return ($0.entries.last?.date ?? .distantPast) > ($1.entries.last?.date ?? .distantPast)
        }
        var chatJSON: [String: Any] = ["players": chat.players.map(personJSON), "histories": try histories.map { history -> [String: Any] in
            let entries = try history.entries.map { entry -> [String: Any] in
                var value = try json(entry) as! [String: Any]
                value["awaiting"] = chat.isAwaiting(entry.id)
                return value
            }
            return ["person": personJSON(history.person), "entries": entries,
                    "inbox": try json(history.inbox ?? ChatInboxState())]
        }]
        if let code = chat.playerCode { chatJSON["playerCode"] = code }
        if let issue = chat.discoveryIssue { chatJSON["discoveryIssue"] = issue }
        if let call = chat.call {
            chatJSON["call"] = ["id": call.id.uuidString, "person": personJSON(call.person), "video": call.video,
                                "phase": String(describing: call.phase), "detail": call.detail]
        }
        result["chat"] = chatJSON
        return result
    }
    private func publish() {
        guard listening, !invalidated else { return }
        do { sendEvent(withName: "stateChanged", body: try snapshot()) }
        catch { NSLog("Vava state refresh failed: %@", error.localizedDescription) }
    }
}
