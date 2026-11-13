import UIKit

@MainActor final class ChatsScreen: ListScreen {
    private var friendsLoaded = false

    override var refreshCompletionMessage: String? { friendsLoaded ? "Updated" : nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Chats"
        toolbar.addArrangedSubview(
            Theme.icon("add", label: "Add a friend") { [weak self] in self?.addFriend() })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
    }

    override func refreshContent() async throws {
        try context.reload()
        draw()
    }

    private func draw() {
        do {
            let friends = try context.library.contacts()
                .filter { !context.state.blocked.contains($0.id) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let drafts = try context.library.savedDrafts()
            let publisherDrafts = context.publishers.filter {
                drafts[$0.id] != nil && !context.state.blocked.contains($0.id)
            }
            var views: [UIView] = []
            if friends.isEmpty {
                let art = UIImageView(image: UIImage(named: "icon-chats"))
                art.contentMode = .scaleAspectFit
                art.heightAnchor.constraint(equalToConstant: 72).isActive = true
                art.isAccessibilityElement = false
                views = [
                    Theme.label("Find your playing partners", size: 24, display: true),
                    Theme.label("Keep in touch between matches.", color: Theme.secondary),
                    Theme.card([
                        art, Theme.label("Add your first friend", size: 22, display: true),
                        Theme.label("Save a friend’s name and email to write them a message."),
                        Theme.button("Add a friend", primary: true) { [weak self] in self?.addFriend() },
                    ]),
                ]
            } else {
                views = [Theme.label("Friends", size: 22, display: true)]
                views += friends.rotated(by: refreshOrder).map { contact in
                    threadRow(contact, draft: drafts[contact.id] ?? "")
                }
            }
            if !publisherDrafts.isEmpty {
                views.append(Theme.label("Publisher drafts", size: 22, display: true))
                views += publisherDrafts.rotated(by: refreshOrder).map { publisher in
                    let contact = ChatContact(id: publisher.id, name: publisher.name, address: nil)
                    return threadRow(contact, publisher: publisher, draft: drafts[publisher.id] ?? "")
                }
            }
            friendsLoaded = true
            render(views)
        } catch {
            friendsLoaded = false
            render([Theme.label("Friends could not be loaded. Pull down to try again.")])
        }
    }

    private func addFriend() {
        push(AddFriendScreen(context) { [weak self] in self?.draw() })
    }

    private func threadRow(_ contact: ChatContact, publisher: Publisher? = nil, draft: String) -> UIView {
        let portrait = publisher.flatMap { context.portrait(for: $0) }
        let open = UIButton(type: .custom)
        open.accessibilityLabel = contact.name
        open.accessibilityHint = "Opens the conversation"
        let avatar = Theme.avatar(44, source: portrait)
        let title = Theme.label(contact.name, size: 18, display: true)
        let subtitle = Theme.label(
            draft.isEmpty ? "Start a conversation" : "Draft: \(draft)", size: 14, color: Theme.secondary)
        subtitle.numberOfLines = 1
        let row = Theme.stack(
            [avatar, Theme.stack([title, subtitle], spacing: 3)], spacing: 12, axis: .horizontal)
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.accessibilityElementsHidden = true
        row.pin(to: open)
        open.accessibilityValue = subtitle.text
        open.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.push(ChatThreadScreen(self.context, contact: contact, publisher: publisher))
            }, for: .touchUpInside)
        return Theme.card([open])
    }
}

@MainActor final class AddFriendScreen: ListScreen {
    private let name = Theme.field("Friend’s name")
    private let email = Theme.field("Email address")
    private let onSave: () -> Void

    init(_ context: AppContext, onSave: @escaping () -> Void) {
        self.onSave = onSave
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Add a friend"
        email.keyboardType = .emailAddress
        email.textContentType = .emailAddress
        email.autocapitalizationType = .none
        email.autocorrectionType = .no
        render([
            name, email,
            Theme.button("Save friend", primary: true) { [weak self] in self?.save() },
        ])
    }

    private func save() {
        let name = name.text?.trimmed ?? ""
        let address = email.text?.trimmed.lowercased() ?? ""
        let emailPattern = #"^[^\s@?,;:/#%]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        guard (1...80).contains(name.count), address.count <= 254,
            address.range(of: emailPattern, options: .regularExpression) != nil
        else {
            show("Check your friend’s details", message: "Enter a name and a valid email address.")
            return
        }
        perform {
            _ = try self.context.library.addContact(name: name, address: address)
            self.onSave()
            self.navigationController?.popViewController(animated: true)
        }
    }
}

@MainActor final class ChatThreadScreen: ListScreen {
    private let contact: ChatContact
    private let publisher: Publisher?
    private let draft = Theme.field("Write a message")
    private let status = Theme.label("", size: 14, color: Theme.lime)

    init(_ context: AppContext, contact: ChatContact, publisher: Publisher? = nil) {
        self.contact = contact
        self.publisher = publisher
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = contact.name
        draft.text = try? context.library.draft(for: contact.id)
        status.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
    }

    override func refreshContent() async throws {
        try context.reload()
        draw()
    }

    private func draw() {
        if context.state.blocked.contains(contact.id) {
            render([Theme.card([Theme.label("This contact is blocked.")])])
            return
        }
        var views: [UIView] = [
            Theme.label(
                contact.address == nil
                    ? "Only you can see this draft." : "Write a message and continue in Mail.",
                color: Theme.secondary),
            draft, status,
            Theme.button("Save draft") { [weak self] in self?.saveDraft() },
        ]
        if let address = contact.address {
            views.append(
                Theme.button("Open in Mail", primary: true) { [weak self] in
                    self?.openMail(address)
                })
        } else if let website = publisher?.website {
            views.append(Theme.button("Visit publisher website") { [weak self] in self?.open(website) })
        }
        render(views)
    }

    private func saveDraft() {
        perform {
            try self.storeDraft()
            self.status.text = "Draft saved"
            self.status.isHidden = false
        }
    }

    private func storeDraft() throws {
        guard !context.state.blocked.contains(contact.id) else {
            throw AppFailure("This contact is blocked.")
        }
        let text = draft.text?.trimmed ?? ""
        guard text.count <= 2000 else {
            throw AppFailure("Use 2,000 characters or fewer.")
        }
        try context.library.saveDraft(text, for: contact.id)
    }

    private func openMail(_ address: String) {
        perform {
            let text = self.draft.text?.trimmed ?? ""
            guard !text.isEmpty else {
                self.show("Write a message", message: "Enter your message before opening Mail.")
                return
            }
            try self.storeDraft()
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = address
            components.queryItems = [URLQueryItem(name: "body", value: text)]
            guard let url = components.url else { return }
            let opened = await UIApplication.shared.open(url)
            if !opened {
                self.show("Could not open Mail", message: "Your draft is saved.")
            }
        }
    }
}
