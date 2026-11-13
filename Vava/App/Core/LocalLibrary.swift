import Foundation

@MainActor final class LocalLibrary {
    private struct Snapshot: Codable {
        var profile: Player
        var agreement: String?
        var signedOut: Bool?
        var deletionPending: Bool?
        var likes: Set<String> = []
        var saves: Set<String> = []
        var hidden: Set<String> = []
        var practice: [String: Set<Int>] = [:]
        var comments: [String: [Discussion]] = [:]
        var submissions: [Submission] = []
        var following: Set<String>?
        var blocked: Set<String>?
        var shareCounts: [String: Int]?
        var reports: [String: ContentReport]?
        var contacts: [String: ChatContact]?
        var drafts: [String: String]?
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

    func shouldResume(_ revision: String) throws -> Bool {
        try hasAccepted(revision) && record?.signedOut != true
    }

    func signOut() throws {
        try update { $0.signedOut = true }
    }

    func open(revision: String, accepted: Bool) throws -> Player {
        try load()
        // The old session filename identifies the wallet owner during the local cutover.
        let previous = previousSession
        let account: UUID
        if let profile = record?.profile {
            account = profile.id
        } else if files.fileExists(atPath: previous.path) {
            account = try JSONDecoder().decode(PreviousSession.self, from: Data(contentsOf: previous)).user.id
        } else {
            account = UUID()
        }
        var next = record ?? Snapshot(profile: Player(id: account, name: "Table tennis player", bio: ""))
        if accepted { next.agreement = revision }
        guard next.agreement == revision else { throw AppFailure("Accept the agreements to continue.") }
        if accepted || next.signedOut == true {
            next.signedOut = nil
            try save(next)
        }
        if files.fileExists(atPath: previous.path) { try files.removeItem(at: previous) }
        return next.profile
    }

    func reload() throws {
        record = try readSnapshot()
    }

    func state() throws -> PersonalState {
        let value = try current()
        return PersonalState(
            me: value.profile, likes: value.likes, saves: value.saves,
            hidden: value.hidden, practice: value.practice,
            following: value.following ?? [], blocked: value.blocked ?? [],
            commentsByClip: value.comments, shareCounts: value.shareCounts ?? [:])
    }

    func setFollowing(_ publisher: String, enabled: Bool) throws {
        try update { snapshot in
            var following = snapshot.following ?? []
            if enabled {
                if !(snapshot.blocked ?? []).contains(publisher) { following.insert(publisher) }
            } else {
                following.remove(publisher)
            }
            snapshot.following = following
        }
    }

    func setBlocked(_ publisher: String, enabled: Bool) throws {
        try update { snapshot in
            var blocked = snapshot.blocked ?? []
            if enabled {
                blocked.insert(publisher)
                snapshot.following?.remove(publisher)
            } else {
                blocked.remove(publisher)
            }
            snapshot.blocked = blocked
        }
    }

    func report(_ target: String, reason: ReportReason) throws {
        try update { snapshot in
            var reports = snapshot.reports ?? [:]
            if reports[target] == nil {
                reports[target] = ContentReport(reason: reason, recordedAt: Date())
            }
            snapshot.reports = reports
            snapshot.hidden.insert(target)
        }
    }

    func recordShare(_ clip: String) throws {
        try update { snapshot in
            var counts = snapshot.shareCounts ?? [:]
            counts[clip, default: 0] += 1
            snapshot.shareCounts = counts
        }
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

    func editProfile(name: String, bio: String, avatarJPEG: Data?) throws {
        try update { $0.profile = Player(id: $0.profile.id, name: name, bio: bio, avatarJPEG: avatarJPEG) }
    }

    func contacts() throws -> [ChatContact] {
        Array((try current().contacts ?? [:]).values)
    }

    func addContact(name: String, address: String) throws -> ChatContact {
        let current = try current()
        if let existing = current.contacts?.values.first(where: { $0.address == address }) {
            return existing
        }
        let contact = ChatContact(id: UUID().uuidString, name: name, address: address)
        try update { snapshot in
            var contacts = snapshot.contacts ?? [:]
            contacts[contact.id] = contact
            snapshot.contacts = contacts
        }
        return contact
    }

    func savedDrafts() throws -> [String: String] {
        try current().drafts ?? [:]
    }

    func draft(for contactID: String) throws -> String {
        try current().drafts?[contactID] ?? ""
    }

    func saveDraft(_ text: String, for contactID: String) throws {
        try update { snapshot in
            var drafts = snapshot.drafts ?? [:]
            drafts[contactID] = text.isEmpty ? nil : text
            snapshot.drafts = drafts
        }
    }

    func post(clip: String, id: UUID, body: String, replyTo: UUID?) throws {
        try update { snapshot in
            var items = snapshot.comments[clip] ?? []
            guard !items.contains(where: { $0.id == id }) else { return }
            let comment = Discussion(
                id: id, author: snapshot.profile, body: body, replyTo: replyTo, postedAt: Date())
            items.insert(comment, at: 0)
            snapshot.comments[clip] = items
        }
    }

    func submissions() throws -> [Submission] { try current().submissions }

    func submissionURL(_ id: UUID) throws -> URL {
        let file = videoURL(id)
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
        try update { snapshot in
            let id = submission.id.uuidString
            snapshot.submissions.removeAll { $0.id == submission.id }
            snapshot.likes.remove(id)
            snapshot.saves.remove(id)
            snapshot.hidden.remove(id)
            snapshot.comments.removeValue(forKey: id)
            snapshot.shareCounts?.removeValue(forKey: id)
        }
        if files.fileExists(atPath: file.path) { try files.removeItem(at: file) }
    }

    func beginAccountDeletion() throws {
        try update { $0.deletionPending = true }
    }

    func finishPendingDeletion() throws {
        try load()
        guard let record, record.deletionPending == true else { return }
        try Wallet.removeLedgers(for: record.profile.id, in: support)
        if files.fileExists(atPath: previousSession.path) { try files.removeItem(at: previousSession) }

        // Keep the deletion marker until imported copies and both wallet files are gone.
        let videos = directory.appendingPathComponent("Videos", isDirectory: true)
        if files.fileExists(atPath: videos.path) { try files.removeItem(at: videos) }
        try files.removeItem(at: index)
        self.record = nil
    }

    private var previousSession: URL {
        support.appendingPathComponent("AuthSessions/buraihehitvpbbtuktye.supabase.co.json")
    }

    private func videoURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("Videos", isDirectory: true)
            .appendingPathComponent(id.uuidString + ".mp4")
    }

    private func load() throws {
        guard record == nil else { return }
        record = try readSnapshot()
    }

    private func readSnapshot() throws -> Snapshot? {
        do {
            return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: index))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func current() throws -> Snapshot {
        try load()
        guard let record else { throw AppFailure("Your profile is unavailable.") }
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
