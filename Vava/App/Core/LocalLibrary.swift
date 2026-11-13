import Foundation

@MainActor final class LocalLibrary {
    private struct Snapshot: Codable {
        var profile: Player
        var agreement: String?
        var likes: Set<String> = []
        var saves: Set<String> = []
        var hidden: Set<String> = []
        var practice: [String: Set<Int>] = [:]
        var comments: [String: [Discussion]] = [:]
        var submissions: [Submission] = []
    }

    private struct PreviousSession: Decodable {
        struct User: Decodable { let id: UUID }
        let user: User
    }

    private let files = FileManager.default
    private let support: URL
    private let directory: URL
    private var record: Snapshot?

    init() throws {
        support = try files.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        directory = support.appendingPathComponent("LocalLibrary", isDirectory: true)
    }

    private var index: URL { directory.appendingPathComponent("library.json") }

    func hasAccepted(_ revision: String) throws -> Bool {
        try load()
        return record?.agreement == revision
    }

    func open(revision: String, accepted: Bool) throws -> Player {
        try load()
        // The old session filename identifies the wallet owner during the local cutover.
        let previous = support.appendingPathComponent("AuthSessions/buraihehitvpbbtuktye.supabase.co.json")
        let account: UUID
        if let profile = record?.profile {
            account = profile.id
        } else if files.fileExists(atPath: previous.path) {
            account = try JSONDecoder().decode(PreviousSession.self, from: Data(contentsOf: previous)).user.id
        } else {
            account = UUID()
        }
        var next = record ?? Snapshot(profile: Player(id: account, name: "Table tennis player", bio: ""))
        if accepted {
            next.agreement = revision
            try save(next)
        }
        guard next.agreement == revision else { throw AppFailure("Accept the agreements to continue.") }
        if files.fileExists(atPath: previous.path) { try files.removeItem(at: previous) }
        return next.profile
    }

    func state() throws -> PersonalState {
        let value = try current()
        return PersonalState(
            me: value.profile, likes: value.likes, saves: value.saves,
            hidden: value.hidden, practice: value.practice)
    }

    func change(_ id: String, kind: Activity, enabled: Bool) throws {
        try update { snapshot in
            let key: WritableKeyPath<Snapshot, Set<String>>
            switch kind {
            case .like: key = \.likes
            case .save: key = \.saves
            case .hide: key = \.hidden
            }
            if enabled { snapshot[keyPath: key].insert(id) } else { snapshot[keyPath: key].remove(id) }
        }
    }

    func markPractice(course: String, step: Int, completed: Bool) throws {
        try update { snapshot in
            if completed {
                snapshot.practice[course, default: []].insert(step)
            } else {
                snapshot.practice[course]?.remove(step)
            }
        }
    }

    func editProfile(name: String, bio: String) throws {
        try update { $0.profile = Player(id: $0.profile.id, name: name, bio: bio) }
    }

    func comments(for clip: String, before: UUID?) throws -> [Discussion] {
        let items = try current().comments[clip] ?? []
        if let before, let index = items.firstIndex(where: { $0.id == before }) {
            return Array(items.dropFirst(index + 1).prefix(50))
        }
        return Array(items.prefix(50))
    }

    func post(clip: String, id: UUID, body: String, replyTo: UUID?) throws {
        try update { snapshot in
            var items = snapshot.comments[clip] ?? []
            guard !items.contains(where: { $0.id == id }) else { return }
            items.insert(Discussion(id: id, author: snapshot.profile, body: body, replyTo: replyTo), at: 0)
            snapshot.comments[clip] = items
        }
    }

    func submissions() throws -> [Submission] { try current().submissions }

    func submissionURL(_ submission: Submission) throws -> URL {
        let file = videoURL(submission.id)
        guard files.fileExists(atPath: file.path) else { throw AppFailure("This video is unavailable.") }
        return file
    }

    func addVideo(from source: URL, id: UUID, title: String) throws {
        var next = try current()
        guard !next.submissions.contains(where: { $0.id == id }) else { return }
        let destination = videoURL(id)
        try files.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
        try files.copyItem(at: source, to: destination)
        next.submissions.insert(Submission(id: id, title: title), at: 0)
        do { try save(next) } catch {
            try? files.removeItem(at: destination)
            throw error
        }
    }

    func removeVideo(_ submission: Submission) throws {
        let file = videoURL(submission.id)
        try update { $0.submissions.removeAll { $0.id == submission.id } }
        if files.fileExists(atPath: file.path) { try files.removeItem(at: file) }
    }

    func delete() throws {
        if files.fileExists(atPath: directory.path) { try files.removeItem(at: directory) }
        record = nil
    }

    private func videoURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("Videos", isDirectory: true)
            .appendingPathComponent(id.uuidString + ".mp4")
    }

    private func load() throws {
        guard record == nil else { return }
        do { record = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: index)) } catch let error
            as CocoaError where error.code == .fileReadNoSuchFile
        { return }
    }

    private func current() throws -> Snapshot {
        try load()
        guard let record else { throw AppFailure("Your local profile is unavailable.") }
        return record
    }

    private func update(_ change: (inout Snapshot) -> Void) throws {
        var next = try current()
        change(&next)
        try save(next)
    }

    private func save(_ snapshot: Snapshot) throws {
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(
            to: index, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        record = snapshot
    }
}
