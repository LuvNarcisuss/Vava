import Foundation

struct ChatPerson: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let isPublisher: Bool

    init(id: String, name: String, isPublisher: Bool = false) {
        self.id = id
        self.name = name
        self.isPublisher = isPublisher
    }

    init(_ publisher: Publisher) {
        self.init(id: publisher.id, name: publisher.name, isPublisher: true)
    }

    var code: String { Self.code(for: id) }

    static func code(for id: String) -> String {
        String(id.dropFirst("player:".count).prefix(8)).uppercased()
    }
}

enum ChatEntryKind: String, Codable, Equatable {
    case incoming, sending, confirmed, unconfirmed, notice
}

struct ChatEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    var kind: ChatEntryKind
}

struct ChatInboxState: Codable, Equatable {
    var pinned = false
    var unread = false
    var hidden = false
}

struct ChatHistory: Codable, Equatable {
    var person: ChatPerson
    var entries: [ChatEntry]
    var inbox: ChatInboxState? = nil
}

enum ChatCallPhase: Equatable {
    case ringing, incoming, connecting, connected, ended
}

struct ChatCall {
    let id: UUID
    let person: ChatPerson
    let video: Bool
    var phase: ChatCallPhase
    var detail: String
}

struct ChatPacket: Codable {
    enum Kind: String, Codable {
        case challenge, identity, following, message, acknowledgement, rejection
        case call, accept, ready, end, audio, video
    }

    let kind: Kind
    var id: UUID?
    var text: String?
    var flag: Bool?
    var data: Data?
    var signature: Data?
}
