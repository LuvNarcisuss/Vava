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
    let estimatedFollowersByPublisherID: [String: Int]
    let shorts: [Clip]
    let courses: [Course]
    let replays: [Replay]
}

struct Clip: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let publisher: String
    let source: URL?
    let license: String
    let licenseURL: URL?
    let media: String
    let cover: String
    let duration: Int
    let publisherID: String
    let engagement: ClipEngagementEstimates
    let editorialComments: [EditorialComment]
    let submissionID: UUID?

    var author: Publisher {
        Publisher(id: publisherID, name: publisher, avatar: nil, website: nil)
    }
}

struct ClipEngagementEstimates: Codable {
    let likes: Int
    let saves: Int
    let shares: Int
}

struct ClipEngagement {
    let likes: Int
    let comments: Int
    let saves: Int
    let shares: Int
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
    let author: Publisher
    let engagement: CourseEngagementEstimates
}

struct CourseEngagementEstimates: Codable {
    let likes: Int
    let saves: Int
}

struct Publisher: Codable, Identifiable {
    let id: String
    let name: String
    let avatar: String?
    let website: URL?
}

enum ReportReason: String, CaseIterable, Codable {
    case harassment = "Harassment or hate"
    case inappropriate = "Inappropriate content"
    case misleading = "Misleading information"
    case rights = "Rights concern"
    case other = "Something else"
}

struct ContentReport: Codable {
    let reason: ReportReason
    let recordedAt: Date
    var wasHidden: Bool?
    var title: String?
}

struct SafetyEvent: Codable {
    enum Action: String, Codable { case report, cancelReport, block, unblock }
    let id: UUID
    let action: Action
    let target: String
    let label: String?
    let reason: ReportReason?
    let date: Date
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
    let avatarJPEG: Data?

    init(id: UUID, name: String, bio: String, avatarJPEG: Data? = nil) {
        self.id = id
        self.name = name
        self.bio = bio
        self.avatarJPEG = avatarJPEG
    }
}

struct ChatContact: Codable, Identifiable {
    let id: String
    let name: String
    let address: String?
}

enum Activity { case like, save, hide }

struct PersonalState {
    let me: Player
    let likes: Set<String>
    let saves: Set<String>
    let hidden: Set<String>
    let practice: [String: Set<Int>]
    let following: Set<String>
    let followers: Set<String>
    let blocked: Set<String>
    let commentsByClip: [String: [Discussion]]
    let shareCounts: [String: Int]

    func discussion(for clip: Clip) -> ClipDiscussion {
        ClipDiscussion(local: commentsByClip[clip.id] ?? [], editorial: clip.editorialComments)
    }

    func engagement(for clip: Clip) -> ClipEngagement {
        ClipEngagement(
            likes: clip.engagement.likes + (likes.contains(clip.id) ? 1 : 0),
            comments: discussion(for: clip).count,
            saves: clip.engagement.saves + (saves.contains(clip.id) ? 1 : 0),
            shares: clip.engagement.shares + (shareCounts[clip.id] ?? 0))
    }

    func engagement(for course: Course) -> (likes: Int, saves: Int) {
        (likes: course.engagement.likes + (likes.contains(course.id) ? 1 : 0),
         saves: course.engagement.saves + (saves.contains(course.id) ? 1 : 0))
    }

    func receivedTotals(for clips: [Clip], courses: [Course] = []) -> (likes: Int, saves: Int) {
        var total = (likes: 0, saves: 0)
        for clip in clips {
            if clip.publisherID == me.id.uuidString {
                total.likes += clip.engagement.likes
                total.saves += clip.engagement.saves
            } else {
                let counts = engagement(for: clip)
                total.likes += counts.likes
                total.saves += counts.saves
            }
        }
        for course in courses {
            let counts = engagement(for: course)
            total.likes += counts.likes
            total.saves += counts.saves
        }
        return total
    }

    func canShow(_ clip: Clip) -> Bool {
        canShow(clip.id, by: clip.publisherID)
    }

    func canShow(_ course: Course) -> Bool {
        canShow(course.id, by: course.author.id)
    }

    private func canShow(_ id: String, by publisherID: String) -> Bool {
        !hidden.contains(id) && !blocked.contains(publisherID)
    }
}

struct Discussion: Codable, Identifiable {
    let id: UUID
    let author: Player
    let body: String
    let replyTo: UUID?
    let postedAt: Date?
}

struct EditorialComment: Codable, Identifiable {
    let id: UUID
    let body: String
}

struct ClipDiscussion {
    let local: [Discussion]
    let editorial: [EditorialComment]

    var count: Int { local.count + editorial.count }

    func author(for id: UUID) -> String? {
        if let author = local.first(where: { $0.id == id })?.author.name { return author }
        return editorial.contains { $0.id == id } ? "Vava Editorial" : nil
    }
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

extension Array {
    func rotated(by offset: Int) -> [Element] {
        guard count > 1 else { return self }
        let remainder = offset % count
        let index = remainder < 0 ? remainder + count : remainder
        guard index != 0 else { return self }
        return Array(self[index...]) + Array(self[..<index])
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
