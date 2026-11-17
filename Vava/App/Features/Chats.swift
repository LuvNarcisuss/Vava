import UIKit

@MainActor final class ChatsScreen: ListScreen, UIScrollViewDelegate {
    private weak var openRow: ChatInboxRow?
    private var displayedRecords: [ChatHistory]?

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Chats"
        scroll.delegate = self
        toolbar.addArrangedSubview(
            Theme.icon("add", label: "Find players") { [weak self] in self?.findPlayers() })
        NotificationCenter.default.addObserver(
            self, selector: #selector(draw(_:)), name: ChatService.changed, object: context.chat)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
    }

    override func refreshContent() async throws {
        try context.reload()
        if context.chat.hasIdentity { try context.chat.start() }
        draw()
    }

    @objc private func draw(_ notification: Notification? = nil) {
        do {
            let records = try context.chat.histories()
            guard records != displayedRecords else { return }
            displayedRecords = records
            openRow = nil
            if records.isEmpty {
                let art = UIImageView(image: UIImage(named: "icon-chats"))
                art.contentMode = .scaleAspectFit
                art.heightAnchor.constraint(equalToConstant: 72).isActive = true
                render([
                    Theme.label("Keep the rally going", size: 25, display: true),
                    Theme.label("Catch up with the players you meet.", color: Theme.secondary),
                    Theme.card([
                        art, Theme.label("Start a conversation", size: 22, display: true),
                        Theme.label("Find a player and follow each other to chat.", color: Theme.secondary),
                        Theme.button("Find players", primary: true) { [weak self] in self?.findPlayers() },
                    ]),
                ])
            } else {
                render(records.map(threadRow))
            }
        } catch {
            displayedRecords = nil
            render([
                Theme.label("Chats could not be loaded. Pull down to try again.", color: Theme.secondary)
            ])
        }
    }

    private func threadRow(_ record: ChatHistory) -> UIView {
        let person = record.person
        let state = record.inbox ?? ChatInboxState()
        let publisher = context.publishers.first { $0.id == person.id }
        let avatar = Theme.avatar(44, source: publisher.flatMap { context.portrait(for: $0) })
        let preview = record.entries.last?.text ?? ""
        let title = Theme.label(person.name, size: 19, display: true)
        let excerpt = Theme.label(preview, size: 14, color: Theme.secondary)
        excerpt.numberOfLines = 1
        var status: [String] = []
        if state.pinned { status.append("Pinned") }
        if state.unread { status.append("Unread") }
        let details = Theme.stack([title, excerpt], spacing: 2)
        if !status.isEmpty {
            details.addArrangedSubview(
                Theme.label(status.joined(separator: " · "), size: 12, color: Theme.lime))
        }
        let row = Theme.stack([avatar, details], spacing: 12, axis: .horizontal)
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.accessibilityElementsHidden = true
        let button = UIButton(type: .custom)
        button.accessibilityLabel = person.name
        button.accessibilityValue = ([preview] + status).joined(separator: ", ")
        row.pin(to: button)
        let card = Theme.card([button])
        if state.pinned { card.layer.borderColor = Theme.lime.cgColor }
        let swipeRow = ChatInboxRow(card: card, state: state, listPan: scroll.panGestureRecognizer) {
            [weak self] action in
            self?.handle(action, for: person)
        }
        swipeRow.onSwipe = { [weak self, weak swipeRow] in
            guard let self, let swipeRow, self.openRow !== swipeRow else { return }
            self.closeActions()
            self.openRow = swipeRow
        }
        button.accessibilityCustomActions = swipeRow.voiceOverActions
        button.addAction(
            UIAction { [weak self] _ in
                guard let self, !self.closeActions() else { return }
                self.push(ChatThreadScreen(self.context, person: person))
            }, for: .touchUpInside)
        return swipeRow
    }

    private func handle(_ action: ChatInboxAction, for person: ChatPerson) {
        closeActions()
        if action == .delete {
            confirm(
                "Delete conversation?", message: "This removes it from Chats until there is new activity.",
                action: "Delete", destructive: true
            ) { [weak self] in
                guard let self else { return }
                self.perform { try self.context.chat.hideConversation(person) }
            }
            return
        }
        perform {
            try self.context.chat.updateInbox(person) { state in
                switch action {
                case .pin: state.pinned.toggle()
                case .read: state.unread.toggle()
                case .delete: break
                }
            }
        }
    }

    @discardableResult
    private func closeActions() -> Bool {
        let row = openRow
        openRow = nil
        guard let row, row.isRevealed else { return false }
        row.close()
        return true
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { closeActions() }

    private func findPlayers() { push(FindPlayersScreen(context)) }
}

@MainActor private enum ChatInboxAction: CaseIterable {
    case pin, read, delete

    func title(for state: ChatInboxState) -> String {
        switch self {
        case .pin: state.pinned ? "Unpin" : "Pin"
        case .read: state.unread ? "Mark read" : "Mark unread"
        case .delete: "Delete"
        }
    }

    var color: UIColor {
        switch self {
        case .pin: Theme.lime
        case .read: Theme.line
        case .delete: Theme.coral
        }
    }
}

@MainActor private final class ChatInboxRow: UIView, UIGestureRecognizerDelegate {
    private let canvas = UIView()
    private let actions = Theme.stack(spacing: 0, axis: .horizontal)
    private weak var listPan: UIPanGestureRecognizer?
    private var offset: CGFloat = 0
    private var dragOrigin: CGFloat = 0
    private(set) var voiceOverActions: [UIAccessibilityCustomAction] = []
    var onSwipe: (() -> Void)?
    var isRevealed: Bool { offset < 0 }

    init(
        card: UIView, state: ChatInboxState, listPan: UIPanGestureRecognizer,
        onAction: @escaping (ChatInboxAction) -> Void
    ) {
        self.listPan = listPan
        super.init(frame: .zero)
        layer.cornerRadius = 20
        clipsToBounds = true
        addSubview(canvas)
        canvas.addSubview(card)
        canvas.addSubview(actions)
        for view in [canvas, card, actions] { view.translatesAutoresizingMaskIntoConstraints = false }
        actions.distribution = .fillEqually
        actions.accessibilityElementsHidden = true
        NSLayoutConstraint.activate([
            canvas.leftAnchor.constraint(equalTo: leftAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leftAnchor.constraint(equalTo: canvas.leftAnchor),
            card.widthAnchor.constraint(equalTo: widthAnchor),
            card.topAnchor.constraint(equalTo: canvas.topAnchor),
            card.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            actions.leftAnchor.constraint(equalTo: card.rightAnchor),
            actions.rightAnchor.constraint(equalTo: canvas.rightAnchor),
            actions.topAnchor.constraint(equalTo: canvas.topAnchor),
            actions.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            actions.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.62),
        ])
        for action in ChatInboxAction.allCases {
            let title = action.title(for: state)
            let button = Theme.button(title) { onAction(action) }
            button.layer.cornerRadius = 0
            button.backgroundColor = action.color
            button.setTitleColor(action == .pin || action == .delete ? Theme.ink : Theme.ivory, for: .normal)
            button.titleLabel?.font = Theme.font(13, display: true)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 3, bottom: 4, right: 3)
            actions.addArrangedSubview(button)
            voiceOverActions.append(
                UIAccessibilityCustomAction(name: title) { _ in
                    onAction(action)
                    return true
                })
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { nil }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer === listPan
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y) * 1.25 && (isRevealed || velocity.x < 0)
    }

    func close() { move(to: 0, animated: true) }

    @objc private func drag(_ pan: UIPanGestureRecognizer) {
        let width = actions.bounds.width
        guard width > 0 else { return }
        switch pan.state {
        case .began:
            dragOrigin = offset
            onSwipe?()
        case .changed:
            move(to: dragOrigin + pan.translation(in: self).x, animated: false)
        case .ended:
            let velocity = pan.velocity(in: self).x
            let revealed = velocity < -400 || (velocity <= 200 && offset < -width * 0.35)
            move(to: revealed ? -width : 0, animated: true)
        case .cancelled, .failed:
            move(to: dragOrigin, animated: true)
        default:
            break
        }
    }

    private func move(to position: CGFloat, animated: Bool) {
        offset = max(-actions.bounds.width, min(0, position))
        let translation = CGAffineTransform(translationX: offset, y: 0)
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.2, delay: 0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) { self.canvas.transform = translation }
        } else {
            canvas.transform = translation
        }
    }
}

@MainActor private final class FindPlayersScreen: ListScreen {
    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Find players"
        NotificationCenter.default.addObserver(
            self, selector: #selector(draw(_:)), name: ChatService.changed, object: context.chat)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
        perform { try self.context.chat.start() }
    }

    override func refreshContent() async throws { try context.chat.start() }
    override var refreshCompletionMessage: String? { nil }

    @objc private func draw(_ notification: Notification? = nil) {
        var views: [UIView] = [
            Theme.label("Open Vava’s Find players screen on both iPhones.", color: Theme.secondary)
        ]
        if let code = context.chat.playerCode {
            views.append(Theme.label("Your player code: \(code)", size: 15, color: Theme.lime))
        }
        if let issue = context.chat.discoveryIssue {
            views.append(Theme.label(issue, color: Theme.secondary))
        } else if context.chat.players.isEmpty {
            views.append(Theme.card([Theme.label("Looking for nearby players…")]))
        }
        views += context.chat.players.map { person in
            Theme.button("\(person.name)  ·  \(person.code)") { [weak self] in
                guard let self else { return }
                self.push(NearbyPlayerScreen(self.context, person: person))
            }
        }
        render(views)
    }
}

@MainActor private final class NearbyPlayerScreen: ListScreen {
    private let person: ChatPerson

    init(_ context: AppContext, person: ChatPerson) {
        self.person = person
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = person.name
        NotificationCenter.default.addObserver(
            self, selector: #selector(draw(_:)), name: ChatService.changed, object: context.chat)
        draw()
    }

    override func refreshContent() async throws { try context.chat.start() }

    @objc private func draw(_ notification: Notification? = nil) {
        let blocked = context.chat.isBlocked(person)
        let following = context.chat.isFollowing(person)
        let follow = Theme.button(following ? "Unfollow" : "Follow", primary: !following) {
            [weak self] in
            guard let self else { return }
            self.perform {
                try self.context.chat.setFollowing(self.person, enabled: !following)
                try self.context.reloadState()
            }
        }
        follow.isEnabled = !blocked
        render([
            Theme.card([
                Theme.label(person.name, size: 24, display: true),
                Theme.label("Player code: \(person.code)", color: Theme.secondary),
            ]),
            follow,
            Theme.button("Message") { [weak self] in
                guard let self else { return }
                self.openChat(with: self.person)
            },
            Theme.button(blocked ? "Unblock" : "Block") { [weak self] in
                guard let self else { return }
                if blocked {
                    self.setBlocked(false)
                } else {
                    self.confirm(
                        "Block \(self.person.name)?",
                        message: "This player will no longer be able to chat or call you.",
                        action: "Block", destructive: true
                    ) { [weak self] in self?.setBlocked(true) }
                }
            },
        ])
    }

    private func setBlocked(_ enabled: Bool) {
        perform {
            try self.context.chat.setBlocked(self.person, enabled: enabled)
            try self.context.reloadState()
        }
    }
}

extension Screen {
    func openChat(with person: ChatPerson) {
        perform {
            let restriction = self.context.chat.restriction(for: person)
            if let restriction { try self.context.chat.recordNotice(restriction, for: person) }
            self.push(ChatThreadScreen(self.context, person: person, entryNotice: restriction))
        }
    }
}

@MainActor final class ChatThreadScreen: ListScreen, UITextFieldDelegate {
    private let person: ChatPerson
    private var entryNotice: String?
    private let input = Theme.field("Message")
    private lazy var sendButton = Theme.button("Send", primary: true) { [weak self] in self?.send() }
    private let hint = Theme.label("", size: 13, color: Theme.secondary)
    private var didShowHistory = false

    init(_ context: AppContext, person: ChatPerson, entryNotice: String? = nil) {
        self.person = person
        self.entryNotice = entryNotice
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = person.name
        heading.font = Theme.font(23, display: true)
        heading.numberOfLines = 1
        heading.lineBreakMode = .byTruncatingTail
        toolbar.addArrangedSubview(
            Theme.icon("call", label: "Voice call") { [weak self] in self?.call(video: false) })
        toolbar.addArrangedSubview(
            Theme.icon("video", label: "Video call") { [weak self] in self?.call(video: true) })
        input.delegate = self
        input.returnKeyType = .send
        let controls = Theme.stack([input, sendButton], spacing: 8, axis: .horizontal)
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        let composer = Theme.stack([hint, controls], spacing: 4)
        composer.backgroundColor = Theme.ink
        view.addSubview(composer)
        composer.translatesAutoresizingMaskIntoConstraints = false
        scrollBottomConstraint?.isActive = false
        NSLayoutConstraint.activate([
            scroll.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            composer.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            composer.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(draw(_:)), name: ChatService.changed, object: context.chat)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            try context.chat.openConversation(person)
        } catch {
            show("Could not mark as read", message: "Open this conversation again to try again.")
        }
        if let entryNotice {
            self.entryNotice = nil
            show("Can’t start chat", message: entryNotice)
        }
        if !person.isPublisher { perform { try self.context.chat.start() } }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        context.chat.closeConversation(person)
    }

    override func refreshContent() async throws {
        try context.reload()
        if !person.isPublisher { try context.chat.start() }
        draw()
    }

    @objc private func draw(_ notification: Notification? = nil) {
        let nearBottom = scroll.contentSize.height - scroll.contentOffset.y - scroll.bounds.height < 90
        let restriction = context.chat.restriction(for: person)
        hint.text = restriction
        hint.isHidden = restriction == nil
        input.isEnabled = restriction == nil
        do {
            let entries = try context.chat.history(for: person)
            render(entries.map(messageRow))
        } catch {
            render([
                Theme.label("Messages could not be loaded. Pull down to try again.", color: Theme.secondary)
            ])
        }
        if nearBottom || !didShowHistory {
            view.layoutIfNeeded()
            let end = max(
                -scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: end), animated: false)
            didShowHistory = true
        }
    }

    private func messageRow(_ entry: ChatEntry) -> UIView {
        if entry.kind == .notice {
            let notice = Theme.label(entry.text, size: 14, color: Theme.secondary)
            notice.textAlignment = .center
            return notice
        }
        let incoming = entry.kind == .incoming
        let text = Theme.label(entry.text, color: incoming ? Theme.ivory : Theme.ink)
        let timestamp = Theme.label(
            entry.date.formatted(.dateTime.month().day().hour().minute()), size: 12,
            color: incoming ? Theme.secondary : Theme.ink)
        var items: [UIView] = [text, timestamp]
        if entry.kind == .sending || entry.kind == .unconfirmed {
            items.append(Theme.label("Awaiting confirmation", size: 12, color: Theme.ink))
            if !context.chat.isAwaiting(entry.id) {
                items.append(Theme.button("Retry") { [weak self] in self?.send(retry: entry) })
            }
        }
        let bubble = Theme.card(items, spacing: 4)
        bubble.backgroundColor = incoming ? Theme.panel : Theme.lime
        let spacer = UIView()
        let row = Theme.stack(
            incoming ? [bubble, spacer] : [spacer, bubble], spacing: 0, axis: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualTo: row.widthAnchor, multiplier: 0.15)
            .isActive = true
        return row
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send()
        return false
    }

    private func send(retry: ChatEntry? = nil) {
        if context.chat.restriction(for: person) == nil,
            (retry?.text ?? input.text ?? "").trimmed.isEmpty
        {
            return
        }
        perform {
            let text = retry?.text ?? self.input.text ?? ""
            if let reason = try self.context.chat.send(text, to: self.person, retry: retry?.id) {
                self.show("Can’t send message", message: reason)
            } else if retry == nil {
                self.input.text = nil
            }
        }
    }

    private func call(video: Bool) {
        perform {
            if let reason = try self.context.chat.requestCall(to: self.person, video: video) {
                self.show("Can’t start call", message: reason)
            } else if let call = self.context.chat.call, !self.presentChatCall(call) {
                self.context.chat.closeCall(call.id)
            }
        }
    }
}

extension Screen {
    func presentChatCall(_ call: ChatCall) -> Bool {
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return false }
        let screen = ChatCallScreen(context, call: call)
        screen.modalPresentationStyle = .fullScreen
        present(screen, animated: true)
        return true
    }
}

@MainActor private final class ChatCallScreen: ListScreen {
    private let initialCall: ChatCall
    private let frame = UIImageView()
    private var muted = false

    init(_ context: AppContext, call: ChatCall) {
        initialCall = call
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = initialCall.video ? "Video call" : "Voice call"
        frame.backgroundColor = Theme.ink
        frame.contentMode = .scaleAspectFit
        frame.clipsToBounds = true
        frame.layer.cornerRadius = 20
        frame.heightAnchor.constraint(equalTo: frame.widthAnchor, multiplier: 1.12).isActive = true
        frame.accessibilityLabel = "Remote video"
        context.chat.onVideoFrame = { [weak self] image in self?.frame.image = image }
        NotificationCenter.default.addObserver(
            self, selector: #selector(draw(_:)), name: ChatService.changed, object: context.chat)
        draw()
    }

    override var refreshCompletionMessage: String? { nil }

    @objc private func draw(_ notification: Notification? = nil) {
        guard let call = context.chat.call, call.id == initialCall.id else {
            dismiss(animated: true)
            return
        }
        let name = Theme.label(call.person.name, size: 26, display: true)
        name.textAlignment = .center
        var views: [UIView] = [name]
        if !call.detail.isEmpty {
            let status = Theme.label(call.detail, color: Theme.secondary)
            status.textAlignment = .center
            views.append(status)
        }
        switch call.phase {
        case .incoming:
            views.append(
                Theme.button("Accept", primary: true) { [weak self] in self?.context.chat.answer(call.id) })
        case .connected:
            if call.video { views.append(frame) }
            views.append(
                Theme.button(muted ? "Unmute" : "Mute") { [weak self] in
                    guard let self else { return }
                    self.muted.toggle()
                    self.context.chat.setMuted(self.muted)
                    self.draw()
                })
        default:
            break
        }
        let endTitle: String
        switch call.phase {
        case .incoming: endTitle = "Decline"
        case .ended: endTitle = "Done"
        default: endTitle = "End call"
        }
        views.append(
            Theme.button(endTitle) { [weak self] in
                guard let self else { return }
                self.context.chat.closeCall(call.id)
            })
        render(views)
    }
}
