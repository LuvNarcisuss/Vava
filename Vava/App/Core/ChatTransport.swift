import CryptoKit
import Foundation
import MultipeerConnectivity

@MainActor final class ChatTransport: NSObject {
    private static let service = "vava-chat"
    private let peer = MCPeerID(displayName: UUID().uuidString)
    private let identity: Curve25519.Signing.PrivateKey
    private let profileName: () -> String
    private lazy var session = MCSession(
        peer: peer, securityIdentity: nil, encryptionPreference: .required)
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: peer, discoveryInfo: nil, serviceType: Self.service)
    private lazy var browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
    private var challenges: [MCPeerID: UUID] = [:]
    private var verified: [MCPeerID: ChatPerson] = [:]
    private(set) var isRunning = false
    var joined: ((ChatPerson) -> Void)?
    var left: ((ChatPerson) -> Void)?
    var received: ((ChatPerson, ChatPacket) -> Void)?
    var failed: (() -> Void)?

    var players: [ChatPerson] { Array(verified.values) }
    var playerCode: String {
        ChatPerson.code(for: Self.playerID(for: identity.publicKey.rawRepresentation))
    }

    private static func playerID(for publicKey: Data) -> String {
        "player:" + publicKey.base64EncodedString()
    }

    init(key: Data, profileName: @escaping () -> String) throws {
        identity = try Curve25519.Signing.PrivateKey(rawRepresentation: key)
        self.profileName = profileName
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        advertiser.delegate = self
        browser.delegate = self
        session.delegate = self
        isRunning = true
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        for person in players { left?(person) }
        challenges.removeAll()
        verified.removeAll()
        session.disconnect()
    }

    @discardableResult
    func send(_ packet: ChatPacket, to person: ChatPerson, reliable: Bool = true) -> Bool {
        guard let peer = verified.first(where: { $0.value.id == person.id })?.key else { return false }
        return send(packet, to: peer, reliable: reliable)
    }

    @discardableResult
    private func send(_ packet: ChatPacket, to peer: MCPeerID, reliable: Bool = true) -> Bool {
        guard isRunning, session.connectedPeers.contains(peer),
            let data = try? JSONEncoder().encode(packet)
        else { return false }
        do {
            try session.send(data, toPeers: [peer], with: reliable ? .reliable : .unreliable)
            return true
        } catch {
            return false
        }
    }

    private func connected(_ remote: MCPeerID) {
        guard isRunning, verified[remote] == nil else { return }
        let nonce = UUID()
        challenges[remote] = nonce
        send(ChatPacket(kind: .challenge, id: nonce), to: remote)
    }

    private static func identityProof(_ nonce: UUID, name: String) -> Data {
        Data("Vava chat identity v1\n\(nonce.uuidString)\n\(name)".utf8)
    }

    private func receive(_ packet: ChatPacket, from remote: MCPeerID) {
        guard isRunning, session.connectedPeers.contains(remote) else { return }
        switch packet.kind {
        case .challenge:
            guard let nonce = packet.id else { return }
            let name = String(profileName().prefix(80))
            guard let signature = try? identity.signature(for: Self.identityProof(nonce, name: name))
            else { return }
            send(
                ChatPacket(
                    kind: .identity, id: nonce, text: name,
                    data: identity.publicKey.rawRepresentation, signature: signature),
                to: remote)
        case .identity:
            guard let nonce = packet.id, challenges[remote] == nonce,
                let raw = packet.data, raw != identity.publicKey.rawRepresentation,
                let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
                let signature = packet.signature, signature.count == 64,
                let name = packet.text, (1...80).contains(name.count), !name.trimmed.isEmpty,
                key.isValidSignature(signature, for: Self.identityProof(nonce, name: name))
            else { return }
            let id = Self.playerID(for: raw)
            guard !verified.values.contains(where: { $0.id == id }) else { return }
            challenges[remote] = nil
            let person = ChatPerson(id: id, name: name)
            verified[remote] = person
            joined?(person)
        default:
            guard let person = verified[remote] else { return }
            received?(person, packet)
        }
    }
}

extension ChatTransport: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate,
    MCNearbyServiceBrowserDelegate
{
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, self.peer.displayName < peerID.displayName,
                !self.session.connectedPeers.contains(peerID)
            else { return }
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor [weak self] in self?.discoveryFailed() }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor [weak self] in self?.discoveryFailed() }
    }

    private func discoveryFailed() {
        guard isRunning else { return }
        stop()
        failed?()
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, peerID.displayName < self.peer.displayName else {
                invitationHandler(false, nil)
                return
            }
            invitationHandler(true, self.session)
        }
    }

    nonisolated func session(
        _ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState
    ) {
        Task { @MainActor [weak self] in
            guard let self, session === self.session, self.isRunning else { return }
            switch state {
            case .connected: self.connected(peerID)
            case .notConnected:
                self.challenges[peerID] = nil
                if let person = self.verified.removeValue(forKey: peerID) { self.left?(person) }
            default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= 100_000, let packet = try? JSONDecoder().decode(ChatPacket.self, from: data)
        else { return }
        Task { @MainActor [weak self] in
            guard let self, session === self.session else { return }
            self.receive(packet, from: peerID)
        }
    }

    nonisolated func session(
        _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) { progress.cancel() }

    nonisolated func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
    ) {}
}
