import AVFoundation
import CryptoKit
import UIKit

@MainActor final class ChatService {
    static let changed = Notification.Name("Vava.ChatChanged")
    private let library: LocalLibrary
    private var transport: ChatTransport?
    private var remoteFollows: [String: Bool] = [:]
    private var pending: Set<UUID> = []
    private var visibleChatID: String?
    private var wantsDiscovery = false
    private var suspended = false
    private var mediaTask: Task<Void, Never>?
    private var ringTimeout: Task<Void, Never>?
    private var mediaTimeout: Task<Void, Never>?
    private var localReady = false
    private var remoteReady = false
    private var media: ChatMedia?
    private(set) var call: ChatCall?
    private(set) var discoveryIssue: String?
    var showIncomingCall: ((ChatCall) -> Bool)?
    var onVideoFrame: ((UIImage) -> Void)?

    init(library: LocalLibrary) { self.library = library }

    var hasIdentity: Bool { (try? library.hasChatIdentity()) == true }
    var playerCode: String? { transport?.playerCode }

    func isAwaiting(_ id: UUID) -> Bool { pending.contains(id) }

    var players: [ChatPerson] {
        (transport?.players ?? []).filter { !isBlocked($0) }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func histories() throws -> [ChatHistory] {
        let blocked = try library.state().blocked
        return try library.chatHistories().filter {
            $0.inbox?.hidden != true && !blocked.contains($0.person.id)
        }.sorted {
            let pinned = $0.inbox?.pinned == true
            if pinned != ($1.inbox?.pinned == true) { return pinned }
            return ($0.entries.last?.date ?? .distantPast) > ($1.entries.last?.date ?? .distantPast)
        }
    }

    func updateInbox(_ person: ChatPerson, _ change: (inout ChatInboxState) -> Void) throws {
        if try library.updateChatInbox(person.id, change) { publish() }
    }

    func hideConversation(_ person: ChatPerson) throws {
        let entries = try history(for: person)
        guard
            try library.updateChatInbox(
                person.id,
                {
                    $0.hidden = true
                    $0.pinned = false
                    $0.unread = false
                })
        else { return }
        pending.subtract(entries.map(\.id))
        publish()
    }

    func openConversation(_ person: ChatPerson) throws {
        visibleChatID = person.id
        try updateInbox(person) { $0.unread = false }
    }

    func closeConversation(_ person: ChatPerson) {
        if visibleChatID == person.id { visibleChatID = nil }
    }

    func history(for person: ChatPerson) throws -> [ChatEntry] {
        guard !isBlocked(person) else { return [] }
        return try library.chatHistories().first { $0.person.id == person.id }?.entries ?? []
    }

    func start() throws {
        wantsDiscovery = true
        guard !suspended else { return }
        if transport == nil {
            let key = try library.chatIdentity(create: {
                Curve25519.Signing.PrivateKey().rawRepresentation
            })
            let link = try ChatTransport(
                key: key,
                profileName: { [weak self] in
                    (try? self?.library.state().me.name) ?? "Table tennis player"
                })
            link.joined = { [weak self] person in self?.join(person) }
            link.left = { [weak self] person in self?.leave(person) }
            link.received = { [weak self] person, packet in self?.receive(packet, from: person) }
            link.failed = { [weak self] in
                self?.discoveryIssue = "Could not find players. Check Vava’s network access in Settings."
                self?.publish()
            }
            transport = link
        }
        discoveryIssue = nil
        transport?.start()
        publish()
    }

    func suspend() {
        suspended = true
        if call?.phase != .ended { finishCall("Call ended", notifyPeer: true) }
        transport?.stop()
        remoteFollows.removeAll()
        publish()
    }

    func resume() {
        suspended = false
        guard wantsDiscovery else { return }
        do { try start() } catch {
            discoveryIssue = "Could not reconnect. Pull down to try again."
            publish()
        }
    }

    func stop() {
        suspend()
        wantsDiscovery = false
        call = nil
        transport = nil
        visibleChatID = nil
        pending.removeAll()
    }

    func isFollowing(_ person: ChatPerson) -> Bool {
        (try? library.state().following.contains(person.id)) == true
    }

    func isBlocked(_ person: ChatPerson) -> Bool {
        (try? library.state().blocked.contains(person.id)) == true
    }

    func setFollowing(_ person: ChatPerson, enabled: Bool) throws {
        guard !person.isPublisher else { return }
        try library.setFollowing(person.id, enabled: enabled)
        sendFollowing(to: person)
        if !enabled, call?.person.id == person.id, call?.phase != .ended {
            finishCall("You must follow each other to call.", notifyPeer: true)
        }
        publish()
    }

    func setBlocked(_ person: ChatPerson, enabled: Bool) throws {
        guard person.id != transport?.localPlayerID,
            person.id != (try library.state().me.id.uuidString)
        else { throw AppFailure("You cannot block yourself.") }
        if enabled && !person.isPublisher {
            let histories = try library.chatHistories()
            let known =
                transport?.players.contains { $0.id == person.id } == true
                || histories.contains { $0.person.id == person.id }
            guard known else { throw AppFailure("This player is unavailable.") }
        }
        try library.setBlocked(person.id, enabled: enabled, person: person)
        sendFollowing(to: person)
        if enabled, call?.person.id == person.id, call?.phase != .ended {
            finishCall("Call ended", notifyPeer: true)
        }
        publish()
    }

    func restriction(for person: ChatPerson) -> String? {
        if isBlocked(person) { return "Unblock this player to chat." }
        if person.isPublisher {
            return "You must follow each other to start a chat. This publisher cannot follow players."
        }
        if !isFollowing(person) { return "You must follow each other to start a chat." }
        guard transport?.players.contains(where: { $0.id == person.id }) == true else {
            return "This player isn’t connected. Open Vava on both devices."
        }
        guard remoteFollows[person.id] == true else { return "You must follow each other to start a chat." }
        return nil
    }

    func recordNotice(_ message: String, for person: ChatPerson) throws {
        let entry = ChatEntry(id: UUID(), text: message, date: Date(), kind: .notice)
        try library.addChatEntry(entry, for: person, coalesceNotice: true)
        publish()
    }

    func send(_ message: String, to person: ChatPerson, retry id: UUID? = nil) throws -> String? {
        if let message = restriction(for: person) {
            try recordNotice(message, for: person)
            return message
        }
        let text = message.trimmed
        guard (1...2000).contains(text.count), text.utf8.count <= 8_000 else {
            throw AppFailure("Write between 1 and 2,000 characters.")
        }
        let id = id ?? UUID()
        let entry = ChatEntry(id: id, text: text, date: Date(), kind: .sending)
        if let existing = try history(for: person).first(where: { $0.id == id }) {
            guard existing.kind == .unconfirmed || (existing.kind == .sending && !isAwaiting(id))
            else { return nil }
            try library.updateChatEntry(id, for: person, to: .sending, showInInbox: true)
        } else {
            try library.addChatEntry(entry, for: person)
        }
        if transport?.send(ChatPacket(kind: .message, id: id, text: text), to: person) == true {
            pending.insert(id)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.pending.remove(id) != nil else { return }
                do {
                    try self.library.updateChatEntry(id, for: person, to: .unconfirmed)
                    try self.recordNotice("The other player hasn’t confirmed this message.", for: person)
                } catch {
                    self.publish()
                }
            }
        } else {
            try library.updateChatEntry(id, for: person, to: .unconfirmed)
            let reason = "This player isn’t connected. Open Vava on both devices."
            try recordNotice(reason, for: person)
            return reason
        }
        publish()
        return nil
    }

    func requestCall(to person: ChatPerson, video: Bool) throws -> String? {
        if let message = restriction(for: person) {
            try recordNotice(message, for: person)
            return message
        }
        guard call == nil else { return "You already have a call open." }
        let id = UUID()
        guard transport?.send(ChatPacket(kind: .call, id: id, flag: video), to: person) == true else {
            return "This player isn’t connected."
        }
        call = ChatCall(id: id, person: person, video: video, phase: .ringing, detail: "Calling…")
        setRingTimeout(id)
        publish()
        return nil
    }

    func answer(_ id: UUID) {
        guard let call, call.id == id, call.phase == .incoming else { return }
        if restriction(for: call.person) != nil {
            finishCall("You must follow each other to call.", notifyPeer: true)
            return
        }
        guard transport?.send(ChatPacket(kind: .accept, id: id), to: call.person) == true else {
            finishCall("This player isn’t connected.", notifyPeer: false)
            return
        }
        connectMedia()
    }

    func closeCall(_ id: UUID) {
        guard let call, call.id == id else { return }
        if call.phase != .ended { finishCall("Call ended", notifyPeer: true) }
        self.call = nil
        onVideoFrame = nil
        publish()
    }

    func setMuted(_ muted: Bool) { media?.muted = muted }

    private func join(_ person: ChatPerson) {
        sendFollowing(to: person)
        publish()
    }

    private func leave(_ person: ChatPerson) {
        remoteFollows.removeValue(forKey: person.id)
        if call?.person.id == person.id, call?.phase != .ended {
            finishCall("Connection lost", notifyPeer: false)
        }
        publish()
    }

    private func sendFollowing(to person: ChatPerson) {
        transport?.send(
            ChatPacket(kind: .following, flag: isFollowing(person) && !isBlocked(person)), to: person)
    }

    private func receive(_ packet: ChatPacket, from person: ChatPerson) {
        switch packet.kind {
        case .following:
            guard let follows = packet.flag else { return }
            let firstUpdate = remoteFollows.updateValue(follows, forKey: person.id) == nil
            do {
                try library.recordIncomingFollow(from: person.id, enabled: follows)
            } catch {
                discoveryIssue = "Could not save this player's follow status."
            }
            if firstUpdate { sendFollowing(to: person) }
            if !follows, call?.person.id == person.id, call?.phase != .ended {
                finishCall("You must follow each other to call.", notifyPeer: true)
            }
            publish()
        case .message:
            guard let id = packet.id, let text = packet.text?.trimmed, (1...2000).contains(text.count),
                text.utf8.count <= 8_000
            else { return }
            guard restriction(for: person) == nil else {
                transport?.send(ChatPacket(kind: .rejection, id: id), to: person)
                return
            }
            do {
                let isVisible = visibleChatID == person.id
                let inserted = try library.addChatEntry(
                    ChatEntry(id: id, text: text, date: Date(), kind: .incoming), for: person,
                    markUnread: !isVisible)
                transport?.send(ChatPacket(kind: .acknowledgement, id: id), to: person)
                if inserted { publish() }
            } catch {
                discoveryIssue = "A message could not be saved."
                publish()
            }
        case .acknowledgement:
            guard let id = packet.id else { return }
            pending.remove(id)
            try? library.updateChatEntry(id, for: person, to: .confirmed)
            publish()
        case .rejection:
            guard let id = packet.id, pending.remove(id) != nil else { return }
            do {
                try library.updateChatEntry(id, for: person, to: .unconfirmed)
                try recordNotice("You must follow each other to send messages.", for: person)
            } catch {
                publish()
            }
        case .call:
            guard let id = packet.id, let video = packet.flag else { return }
            guard call == nil, restriction(for: person) == nil else {
                transport?.send(ChatPacket(kind: .end, id: id), to: person)
                return
            }
            let incoming = ChatCall(
                id: id, person: person, video: video, phase: .incoming, detail: "Incoming call")
            call = incoming
            guard showIncomingCall?(incoming) == true else {
                closeCall(id)
                return
            }
            setRingTimeout(id)
            publish()
        case .accept:
            guard matches(packet, person), call?.phase == .ringing else { return }
            connectMedia()
        case .ready:
            guard matches(packet, person), call?.phase == .connecting else { return }
            remoteReady = true
            updateCallReadiness()
        case .end:
            guard matches(packet, person) else { return }
            finishCall("Call ended", notifyPeer: false)
        case .audio:
            guard matches(packet, person), call?.phase == .connected, let data = packet.data else {
                return
            }
            media?.play(data)
        case .video:
            guard matches(packet, person), call?.phase == .connected, call?.video == true,
                let data = packet.data
            else { return }
            media?.showFrame(data)
        case .challenge, .identity:
            break
        }
    }

    private func matches(_ packet: ChatPacket, _ person: ChatPerson) -> Bool {
        guard let call, call.phase != .ended else { return false }
        return call.person.id == person.id && call.id == packet.id
    }

    private func setRingTimeout(_ id: UUID) {
        ringTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.call?.id == id else { return }
            self.finishCall("No answer", notifyPeer: true)
        }
    }

    private func connectMedia() {
        guard let call else { return }
        ringTimeout?.cancel()
        self.call?.phase = .connecting
        self.call?.detail = "Connecting…"
        localReady = false
        remoteReady = false
        publish()
        mediaTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(40))
            guard !Task.isCancelled, let self, self.call?.id == call.id else { return }
            self.finishCall("Could not connect the call.", notifyPeer: true)
        }
        mediaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let media = ChatMedia(
                    sendAudio: { [weak self] data in self?.sendMedia(data, kind: .audio) },
                    sendVideo: { [weak self] data in self?.sendMedia(data, kind: .video) },
                    renderVideo: { [weak self] frame in self?.onVideoFrame?(frame) },
                    interrupted: { [weak self] in self?.finishCall("Call interrupted", notifyPeer: true) })
                self.media = media
                try await media.start(video: call.video)
                guard !Task.isCancelled, self.call?.id == call.id, self.call?.phase == .connecting
                else {
                    media.stop()
                    return
                }
                self.localReady = true
                guard self.transport?.send(ChatPacket(kind: .ready, id: call.id), to: call.person) == true
                else {
                    self.finishCall("Connection lost", notifyPeer: false)
                    return
                }
                self.updateCallReadiness()
            } catch {
                if !Task.isCancelled, self.call?.id == call.id {
                    self.finishCall(
                        (error as? AppFailure)?.message ?? "Could not start the call.", notifyPeer: true)
                }
            }
        }
    }

    private func sendMedia(_ data: Data, kind: ChatPacket.Kind) {
        guard let call, call.phase == .connected else { return }
        transport?.send(
            ChatPacket(kind: kind, id: call.id, data: data), to: call.person, reliable: false)
    }

    private func updateCallReadiness() {
        guard localReady, remoteReady, call?.phase == .connecting else { return }
        mediaTimeout?.cancel()
        call?.phase = .connected
        call?.detail = ""
        publish()
    }

    private func finishCall(_ detail: String, notifyPeer: Bool) {
        guard let call, call.phase != .ended else { return }
        if notifyPeer { transport?.send(ChatPacket(kind: .end, id: call.id), to: call.person) }
        ringTimeout?.cancel()
        mediaTimeout?.cancel()
        mediaTask?.cancel()
        media?.stop()
        media = nil
        self.call?.phase = .ended
        self.call?.detail = detail
        publish()
    }

    private func publish() { NotificationCenter.default.post(name: Self.changed, object: self) }
}
