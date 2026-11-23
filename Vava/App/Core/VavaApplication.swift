import SafariServices
import UIKit

@MainActor final class AppContext {
    let library: LocalLibrary
    let wallet: Wallet
    let catalog: Catalog
    lazy var chat = ChatService(library: library)
    private(set) var state: PersonalState
    var leave: ((String?) -> Void)?

    init(library: LocalLibrary, wallet: Wallet, catalog: Catalog) throws {
        self.library = library
        self.wallet = wallet
        self.catalog = catalog
        state = try library.state()
    }

    func reload() throws {
        try library.reload()
        try reloadState()
    }
    func reloadState() throws { state = try library.state() }

    func change(_ target: String, kind: Activity, enabled: Bool) throws {
        try library.change(target, kind: kind, enabled: enabled)
        try reloadState()
    }

    func report(_ target: String, reason: ReportReason) throws {
        guard
            catalog.shorts.contains(where: { $0.id == target })
                || catalog.courses.contains(where: { $0.id == target })
        else { throw AppFailure("This content is unavailable.") }
        try library.report(target, reason: reason)
        try reloadState()
    }

    func setBlocked(_ publisher: Publisher, enabled: Bool) throws {
        guard publishers.contains(where: { $0.id == publisher.id }) else {
            throw AppFailure("This publisher could not be found.")
        }
        try library.setBlocked(publisher.id, enabled: enabled)
        try reloadState()
    }

    func portrait(for publisher: Publisher) -> URL? {
        (publisher.avatar ?? catalog.shorts.first { $0.publisherID == publisher.id }?.cover).flatMap {
            asset($0)
        }
    }

    var publishers: [Publisher] {
        var seen: Set<String> = []
        return (catalog.shorts.map(\.author) + catalog.courses.map(\.author))
            .filter { seen.insert($0.id).inserted }
    }

    func asset(_ path: String) -> URL? {
        Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "Media")
    }

    func ownedClips(from submissions: [Submission]) -> [Clip] {
        submissions.map { submission in
            Clip(
                id: submission.id.uuidString, title: submission.title, detail: "From your works.",
                publisher: state.me.name, source: nil, license: "", licenseURL: nil,
                media: "", cover: "", duration: 0, publisherID: state.me.id.uuidString,
                engagement: ClipEngagementEstimates(likes: 0, saves: 0, shares: 0),
                editorialComments: [], submissionID: submission.id)
        }
    }

    func videoURL(for clip: Clip) throws -> URL {
        if let id = clip.submissionID {
            return try library.submissionURL(id)
        }
        guard let url = asset(clip.media) else { throw AppFailure("This video is unavailable.") }
        return url
    }

    func signOut() throws {
        try library.signOut()
        chat.stop()
        wallet.stop()
        leave?(nil)
    }

    func deleteAccount() throws {
        try library.beginAccountDeletion()
        chat.stop()
        wallet.stop()
        do {
            try library.finishPendingDeletion()
            leave?(nil)
        } catch {
            leave?("Account deletion could not finish. Pull down to try again.")
        }
    }
}

@main @MainActor final class VavaApplication: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var library: LocalLibrary?
    private weak var activeContext: AppContext?
    private var loading = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        showWelcome()
        window.makeKeyAndVisible()
        Task {
            do {
                try await self.restoreWelcome()
            } catch {
                ((window.rootViewController as? UINavigationController)?.viewControllers.first as? WelcomeScreen)?
                    .showError("Your library could not be opened. Please try again.")
            }
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) { activeContext?.chat.suspend() }

    func applicationWillEnterForeground(_ application: UIApplication) { activeContext?.chat.resume() }

    private func openLibrary() throws -> LocalLibrary {
        if let library { return library }
        let opened = try LocalLibrary()
        library = opened
        return opened
    }

    private func showWelcome(message: String? = nil) {
        let welcome = WelcomeScreen()
        welcome.onContinue = { [weak self] accepted in Task { await self?.enter(accepted: accepted) } }
        welcome.onRefresh = { [weak self] in try await self?.restoreWelcome() }
        window?.rootViewController = UINavigationController(rootViewController: welcome)
        if let message { welcome.showError(message) }
    }

    private func restoreWelcome() async throws {
        let library = try openLibrary()
        try library.reload()
        try library.finishPendingDeletion()
    }

    private func enter(accepted: Bool) async {
        guard !loading, let nav = window?.rootViewController as? UINavigationController,
            let welcome = nav.viewControllers.first as? WelcomeScreen
        else { return }
        loading = true
        welcome.setLoading(true)
        defer {
            loading = false
            welcome.setLoading(false)
        }
        do {
            guard let catalog: Catalog = Bundle.main.decode("catalog") else {
                throw AppFailure("Videos and lessons could not be loaded.")
            }
            let library = try openLibrary()
            try library.finishPendingDeletion()
            guard accepted else { throw AppFailure("Accept the agreements to continue.") }
            let needsConsent = try !library.hasAccepted(Agreement.revision)
            let profile = try library.open(revision: Agreement.revision, accepted: needsConsent)
            let context = try AppContext(
                library: library, wallet: Wallet(account: profile.id), catalog: catalog)
            context.leave = { [weak self] message in
                self?.activeContext = nil
                self?.showWelcome(message: message)
            }
            activeContext = context
            window?.rootViewController = Dock(context)
        } catch {
            welcome.showError((error as? AppFailure)?.message ?? "Vava could not open. Please try again.")
        }
    }
}

enum Agreement: String, CaseIterable {
    case terms = "Terms of Service"
    case privacy = "Privacy Policy"

    static let revision = "2026-11-13.2"
    private var url: URL {
        switch self {
        case .terms:
            return URL(
                string: "https://docs.google.com/document/d/1HKDBNvyA7Vha5_sVVoc4P4Z8e-udZkrMlfdbTgVvdOs")!
        case .privacy:
            return URL(
                string: "https://docs.google.com/document/d/1_ldTUi2Y1bfT5x9BphLfDo3AwM7ZBpNxUnHFmwI2GFo")!
        }
    }

    @MainActor func open(from controller: UIViewController) {
        controller.present(SFSafariViewController(url: url), animated: true)
    }
}

@MainActor final class WelcomeScreen: UIViewController {
    private static let consentRequiredMessage = "Accept the agreements to continue."

    var onContinue: ((Bool) -> Void)?
    private var isOpening = false
    var onRefresh: (() async throws -> Void)?
    private let scroll = UIScrollView()
    private let refresh = UIRefreshControl()
    private let feedback = RefreshFeedback()
    private var accepted = false
    private let consentLabel = Theme.label("I agree to the", size: 15)
    private let status = Theme.label("", color: Theme.coral)
    private let cover = UIImageView(image: UIImage(named: "brand-logo"))
    private lazy var accept = Theme.icon("check", label: "Accept the agreements") { [weak self] in
        guard let self else { return }
        self.accepted.toggle()
        if self.accepted, self.status.text == Self.consentRequiredMessage {
            self.status.text = nil
            self.status.isHidden = true
        }
        self.updateCheckbox()
    }
    private lazy var enter = Theme.button("Log in", primary: true) { [weak self] in
        guard let self else { return }
        guard self.accepted else {
            self.showError(Self.consentRequiredMessage)
            return
        }
        self.onContinue?(self.accepted)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        Theme.fill(view)
        cover.contentMode = .scaleAspectFit
        cover.isAccessibilityElement = true
        cover.accessibilityLabel = "Vava logo"
        let logoArea = UIView()
        cover.translatesAutoresizingMaskIntoConstraints = false
        logoArea.addSubview(cover)
        NSLayoutConstraint.activate([
            cover.widthAnchor.constraint(equalToConstant: 144),
            cover.heightAnchor.constraint(equalTo: cover.widthAnchor),
            cover.centerXAnchor.constraint(equalTo: logoArea.centerXAnchor),
            cover.centerYAnchor.constraint(equalTo: logoArea.centerYAnchor),
            logoArea.heightAnchor.constraint(greaterThanOrEqualTo: cover.heightAnchor),
        ])
        let subtitle = Theme.label(
            "Watch the point. Practice the shot. Find your next partner.", color: Theme.secondary)
        let agreements = Agreement.allCases.map { agreement in
            let button = UIButton(type: .custom)
            button.setAttributedTitle(
                NSAttributedString(
                    string: agreement.rawValue,
                    attributes: [
                        .font: Theme.font(16), .foregroundColor: Theme.ivory,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ]), for: .normal)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(
                UIAction { [weak self] _ in
                    guard let self else { return }
                    agreement.open(from: self)
                }, for: .touchUpInside)
            return button
        }
        let links = Theme.stack(agreements, spacing: 10, axis: .horizontal)
        links.alignment = .leading
        let consent = Theme.stack(
            [accept, Theme.stack([consentLabel, links], spacing: 0)],
            axis: .horizontal)
        consent.alignment = .center
        status.isHidden = true
        let content = Theme.stack([logoArea, subtitle, consent, status, enter], spacing: 9)
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let safe = view.safeAreaLayoutGuide
        let frame = scroll.frameLayoutGuide
        let layout = scroll.contentLayoutGuide
        let fitHeight = content.heightAnchor.constraint(equalTo: frame.heightAnchor, constant: -20)
        fitHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safe.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            content.topAnchor.constraint(equalTo: layout.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: layout.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: layout.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: layout.bottomAnchor, constant: -10),
            content.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -40),
            fitHeight,
        ])
        scroll.alwaysBounceVertical = true
        refresh.tintColor = Theme.lime
        refresh.addTarget(self, action: #selector(refreshWelcome), for: .valueChanged)
        scroll.refreshControl = refresh
        enter.setTitleColor(Theme.secondary, for: .disabled)
        updateCheckbox()
    }

    @objc private func refreshWelcome() {
        Task { [weak self] in
            guard let self else { return }
            defer { self.refresh.endRefreshing() }
            do {
                try await self.onRefresh?()
                if self.view.window != nil {
                    self.status.isHidden = true
                    self.feedback.show(in: self.view)
                }
            } catch {
                self.showError("Vava could not refresh. Pull down to try again.")
            }
        }
    }

    private func updateCheckbox() {
        enter.isEnabled = accepted && !isOpening
        enter.backgroundColor = enter.isEnabled ? Theme.lime : Theme.panel
        accept.isEnabled = !isOpening
        accept.layer.cornerRadius = 12
        accept.backgroundColor = accepted ? Theme.lime : Theme.panel
        accept.subviews.first?.alpha = accepted ? 1 : 0.24
        accept.accessibilityValue = accepted ? "Checked" : "Unchecked"
        accept.accessibilityTraits = accepted ? [.button, .selected] : [.button]
    }

    func setLoading(_ loading: Bool) {
        loadViewIfNeeded()
        isOpening = loading
        enter.setTitle(loading ? "Opening…" : "Log in", for: .normal)
        updateCheckbox()
    }

    func showError(_ message: String) {
        loadViewIfNeeded()
        status.text = message
        status.isHidden = false
    }
}

@MainActor final class Dock: UITabBarController, UITabBarControllerDelegate, UINavigationControllerDelegate {
    private let context: AppContext
    private let strip = UIStackView()
    private var controls: [UIButton] = []

    init(_ context: AppContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        tabBar.isHidden = true
        delegate = self
        context.chat.showIncomingCall = { [weak self] call in
            guard let self, self.presentedViewController == nil,
                let navigation = self.selectedViewController as? UINavigationController,
                navigation.presentedViewController == nil,
                let screen = navigation.topViewController as? Screen
            else { return false }
            return screen.presentChatCall(call)
        }
        let roots: [(String, String, UIViewController)] = [
            ("Academy", "academy", AcademyScreen(context)),
            ("Watch", "watch", WatchScreen(context)),
            ("Shorts", "shorts", ShortsScreen(context)),
            ("Chats", "chats", ChatsScreen(context)),
            ("Me", "me", ProfileScreen(context)),
        ]
        setViewControllers(
            roots.map { entry in
                let nav = UINavigationController(rootViewController: entry.2)
                nav.setNavigationBarHidden(true, animated: false)
                nav.delegate = self
                return nav
            }, animated: false)
        selectedIndex = 0
        strip.axis = .horizontal
        strip.distribution = .fillEqually
        strip.backgroundColor = Theme.ink
        strip.layer.cornerRadius = 22
        strip.layer.borderWidth = 1
        strip.layer.borderColor = Theme.line.cgColor
        view.addSubview(strip)
        strip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 13),
            strip.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -13),
            strip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            strip.heightAnchor.constraint(equalToConstant: 62),
        ])
        for (index, entry) in roots.enumerated() {
            let button = UIButton(type: .custom)
            let icon = UIImageView(image: UIImage(named: "icon-" + entry.1))
            icon.contentMode = .scaleAspectFit
            icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
            let label = Theme.label(entry.0, size: 12, display: true)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.numberOfLines = 1
            let content = Theme.stack([icon, label], spacing: 0)
            content.isUserInteractionEnabled = false
            content.pin(to: button, top: 5, left: 1, bottom: 4, right: 1)
            button.layer.cornerRadius = 20
            button.accessibilityLabel = entry.0
            button.addAction(
                UIAction { [weak self] _ in
                    guard let self else { return }
                    self.selectedIndex = index
                    self.sync()
                }, for: .touchUpInside)
            controls.append(button)
            strip.addArrangedSubview(button)
        }
        sync()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if context.chat.hasIdentity { try? context.chat.start() }
    }

    private func sync() {
        strip.isHidden = (selectedViewController as? UINavigationController)?.viewControllers.count != 1
        for (index, button) in controls.enumerated() {
            button.backgroundColor = index == selectedIndex ? Theme.line : .clear
            button.accessibilityTraits = index == selectedIndex ? [.button, .selected] : [.button]
        }
        view.bringSubviewToFront(strip)
    }

    func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        sync()
    }
}
