import UIKit

@MainActor final class DiscussionSheet: Screen {
    private let clip: Clip
    private let onChange: () -> Void
    private let onClose: () -> Void
    private let panel = UIView()
    private let rows = Theme.stack(spacing: 8)
    private let scroll = UIScrollView()
    private let field = Theme.field("Add a private comment")
    private let replyLabel = Theme.label("", color: Theme.lime)
    private let titleLabel = Theme.label("", size: 25, display: true)
    private let composer = Theme.stack(spacing: 6)
    private var reply: (id: UUID, author: String)?
    private let pageSize = 30
    private var visibleCount = 30
    private var closing = false
    private let refresh = UIRefreshControl()
    private var editorialOrder = 0

    init(_ context: AppContext, clip: Clip, onChange: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.clip = clip
        self.onChange = onChange
        self.onClose = onClose
        super.init(context)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        let backdrop = UIControl()
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.16)
        backdrop.pin(to: view)
        backdrop.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)

        panel.backgroundColor = Theme.ink
        panel.layer.cornerRadius = 24
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.clipsToBounds = true
        view.addSubview(panel)
        panel.translatesAutoresizingMaskIntoConstraints = false
        let midpoint = view.centerYAnchor
        let half = panel.topAnchor.constraint(equalTo: midpoint)
        half.priority = .defaultHigh
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),
            half,
        ])

        titleLabel.accessibilityTraits.insert(.header)
        let heading = Theme.stack(
            [
                titleLabel,
                Theme.icon("close", label: "Close comments") { [weak self] in self?.close() },
            ], spacing: 8, axis: .horizontal)
        heading.alignment = .center
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipe.direction = .down
        heading.addGestureRecognizer(swipe)

        let save = Theme.button("Save", primary: true) { [weak self] in self?.send() }
        save.setContentHuggingPriority(.required, for: .horizontal)
        save.setContentCompressionResistancePriority(.required, for: .horizontal)
        save.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let entry = Theme.stack([field, save], spacing: 8, axis: .horizontal)
        entry.alignment = .center
        composer.addArrangedSubview(entry)
        scroll.keyboardDismissMode = .onDrag
        scroll.alwaysBounceVertical = true
        refresh.tintColor = Theme.lime
        refresh.addTarget(self, action: #selector(refreshComments), for: .valueChanged)
        scroll.refreshControl = refresh
        rows.pin(to: scroll, bottom: 8)
        rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor).isActive = true
        let content = Theme.stack([heading, scroll, composer], spacing: 6)
        content.pin(to: panel, top: 6, left: 18, bottom: 10, right: 18)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        draw()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        panel.transform = CGAffineTransform(
            translationX: 0, y: panel.bounds.height + view.safeAreaInsets.bottom)
        UIView.animate(withDuration: 0.26) { self.panel.transform = .identity }
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    @objc private func close() {
        guard !closing else { return }
        closing = true
        view.endEditing(true)
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.0 : 0.22
        UIView.animate(
            withDuration: duration,
            animations: {
                self.panel.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                self.view.alpha = 0
            }, completion: { _ in self.dismiss(animated: false, completion: self.onClose) })
    }

    @objc private func refreshComments() {
        defer { refresh.endRefreshing() }
        do {
            try context.reload()
            editorialOrder += 1
            draw()
            onChange()
            refreshFeedback.show(in: panel, message: "Comments updated")
        } catch {
            show("Could not refresh comments", message: "Pull down to try again.")
        }
    }

    private func draw() {
        let discussion = context.state.discussion(for: clip)
        let total = discussion.count
        titleLabel.text = total == 1 ? "1 comment" : "\(total.formatted()) comments"
        for row in rows.arrangedSubviews { row.removeFromSuperview() }

        if total == 0 {
            rows.addArrangedSubview(
                Theme.label(
                    "No comments yet. Add a private comment.", size: 14, color: Theme.secondary))
        } else if !discussion.editorial.isEmpty {
            rows.addArrangedSubview(
                Theme.label(
                    "Vava’s notes follow the footage. Comments you add are private.", size: 14,
                    color: Theme.secondary))
        }
        let local = discussion.local.prefix(visibleCount)
        for comment in local {
            let parent = comment.replyTo.flatMap { discussion.author(for: $0) }
            let status = parent.map { "Private · Reply to \($0)" } ?? "Private comment"
            let date = comment.postedAt?.formatted(date: .abbreviated, time: .shortened)
            let detail = [status, date].compactMap { $0 }.joined(separator: " · ")
            rows.addArrangedSubview(
                commentCard(id: comment.id, author: comment.author.name, body: comment.body, detail: detail))
        }
        for note in discussion.editorial.rotated(by: editorialOrder).prefix(visibleCount - local.count) {
            rows.addArrangedSubview(commentCard(id: note.id, author: "Vava Editorial", body: note.body))
        }
        if visibleCount < total {
            rows.addArrangedSubview(
                Theme.button("More comments") { [weak self] in
                    guard let self else { return }
                    self.visibleCount += self.pageSize
                    self.draw()
                })
        }
    }

    private func commentCard(id: UUID, author: String, body: String, detail: String? = nil) -> UIView {
        let replyButton = Theme.button("Reply") { [weak self] in
            self?.setReply((id, author))
            self?.field.becomeFirstResponder()
        }
        var content: [UIView] = [Theme.label(author, size: 16, display: true)]
        if let detail {
            content.append(Theme.label(detail, size: 13, color: Theme.lime))
        }
        content.append(contentsOf: [Theme.label(body, size: 16), replyButton])
        return Theme.card(content, spacing: 4)
    }

    private func setReply(_ comment: (id: UUID, author: String)?) {
        reply = comment
        if composer.arrangedSubviews.count > 1 {
            composer.arrangedSubviews.first?.removeFromSuperview()
        }
        guard let comment else { return }
        replyLabel.text = "Replying to \(comment.author)"
        let row = Theme.stack(
            [
                replyLabel, Theme.icon("close", label: "Cancel reply") { [weak self] in self?.setReply(nil) },
            ], axis: .horizontal)
        composer.insertArrangedSubview(row, at: 0)
    }

    private func send() {
        let body = field.text?.trimmed ?? ""
        guard !body.isEmpty else { return }
        guard body.count <= 200 else {
            show("Comment is too long", message: "Use 200 characters or fewer.")
            return
        }
        do {
            try context.library.post(clip: clip.id, id: UUID(), body: body, replyTo: reply?.id)
            try context.reloadState()
            field.text = nil
            setReply(nil)
            draw()
            scroll.setContentOffset(.zero, animated: true)
            onChange()
        } catch {
            show("Could not save the comment", message: "Try saving your comment again.")
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
            Theme.label("This hides the video from your lists."),
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
