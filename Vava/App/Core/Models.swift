import Foundation

extension Bundle {
    func decode<T: Decodable>(_ name: String) -> T? {
        guard let url = url(forResource: name, withExtension: "json"),
            let bytes = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: bytes)
    }
}

struct Catalog: Codable {
    let shorts: [Clip]
    let courses: [Course]
    let replays: [Replay]
}

struct Clip: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let publisher: String
    let source: URL
    let license: String
    let licenseURL: URL
    let media: String
    let cover: String
    let duration: Int
}

struct Course: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let level: String
    let detail: String
    let price: Int
    let minutes: Int
    let cover: String
    let steps: [String]?
    let reference: URL
    let referenceName: String
}

struct Replay: Codable, Identifiable {
    let id: String
    let title: String
    let event: String
    let publisher: String
    let source: URL
    let cover: String
}

struct Player: Codable, Identifiable {
    let id: UUID
    let name: String
    let bio: String
}

enum Activity { case like, save, hide }

struct PersonalState {
    let me: Player
    let likes: Set<String>
    let saves: Set<String>
    let hidden: Set<String>
    let practice: [String: Set<Int>]
}

struct Discussion: Codable, Identifiable {
    let id: UUID
    let author: Player
    let body: String
    let replyTo: UUID?
}

struct Submission: Codable, Identifiable {
    let id: UUID
    let title: String
}

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
