import UIKit

@MainActor final class DiscussionScreen: ListScreen {
    private let clip: Clip
    private var comments: [Discussion] = []
    private let text = Theme.field("Add a private note")
    private let replyLabel = Theme.label("", color: Theme.lime)
    private var reply: Discussion?
    private var loading = false
    private var canPage = true
    private var sending = false
    private var attempt: (id: UUID, body: String, reply: UUID?)?

    init(_ context: AppContext, clip: Clip) {
        self.clip = clip
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Clip notes"
        draw()
        perform { try await self.refreshContent() }
    }

    override func refreshContent() async throws { try await load(older: false) }

    private func load(older: Bool) async throws {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let result = try context.library.comments(for: clip.id, before: older ? comments.last?.id : nil)
        canPage = result.count == 50
        if older { comments += result } else { comments = result }
        draw()
    }

    private func draw() {
        let input = Theme.stack(
            [text, Theme.button("Save", primary: true) { [weak self] in self?.send() }], spacing: 7,
            axis: .horizontal)
        var views: [UIView] = [Theme.label(clip.title, color: Theme.secondary)]
        if let reply {
            replyLabel.text = "Replying to \(reply.author.name)"
            views.append(
                Theme.stack(
                    [
                        replyLabel,
                        Theme.icon("close", label: "Cancel reply") { [weak self] in
                            self?.reply = nil
                            self?.draw()
                        },
                    ], axis: .horizontal))
        }
        views.append(input)
        if comments.isEmpty {
            views.append(Theme.label("Your notes are saved on this device.", color: Theme.secondary))
        }
        for comment in comments {
            var content: [UIView] = [
                Theme.label(comment.author.name, display: true),
                Theme.label(comment.body),
            ]
            if let parent = comment.replyTo {
                let name = comments.first { $0.id == parent }?.author.name
                content.insert(
                    Theme.label(name.map { "In reply to \($0)" } ?? "Reply", size: 14, color: Theme.secondary),
                    at: 1)
            }
            let row = Theme.stack(axis: .horizontal)
            row.addArrangedSubview(
                Theme.button("Reply") { [weak self] in
                    self?.reply = comment
                    self?.draw()
                    self?.text.becomeFirstResponder()
                })
            content.append(row)
            views.append(Theme.card(content))
        }
        if canPage, !comments.isEmpty {
            views.append(
                Theme.button("Earlier notes") { [weak self] in
                    guard let self else { return }
                    self.perform { try await self.load(older: true) }
                })
        }
        render(views)
    }

    private func send() {
        let body = text.text?.trimmed ?? ""
        guard !sending, !body.isEmpty else { return }
        guard body.count <= 200 else {
            show("Note is too long", message: "Use 200 characters or fewer.")
            return
        }
        let replyID = reply?.id
        let id = attempt.flatMap { $0.body == body && $0.reply == replyID ? $0.id : nil } ?? UUID()
        attempt = (id, body, replyID)
        sending = true
        perform {
            defer { self.sending = false }
            try self.context.library.post(clip: self.clip.id, id: id, body: body, replyTo: replyID)
            self.attempt = nil
            if self.text.text?.trimmed == body { self.text.text = nil }
            if self.reply?.id == replyID { self.reply = nil }
            try await self.refreshContent()
        }
    }
}

@MainActor final class HideContentScreen: ListScreen {
    private let target: String
    private let completed: () -> Void

    init(_ context: AppContext, target: String, completed: @escaping () -> Void) {
        self.target = target
        self.completed = completed
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Hide this video"
        render([
            Theme.label("This removes the video from your lists on this device."),
            Theme.button("Hide video", primary: true) { [weak self] in
                guard let self else { return }
                self.perform {
                    try self.context.change(self.target, kind: .hide, enabled: true)
                    self.navigationController?.popViewController(animated: true)
                    self.completed()
                }
            },
        ])
    }
}
