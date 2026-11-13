import PDFKit
import UIKit

@MainActor final class AppContext {
    let library: LocalLibrary
    let wallet: Wallet
    let catalog: Catalog
    private(set) var state: PersonalState
    var leave: (() -> Void)?

    init(library: LocalLibrary, wallet: Wallet, catalog: Catalog) throws {
        self.library = library
        self.wallet = wallet
        self.catalog = catalog
        state = try library.state()
    }

    func reload() throws { try reloadState() }
    func reloadState() throws { state = try library.state() }

    func change(_ target: String, kind: Activity, enabled: Bool) throws {
        try library.change(target, kind: kind, enabled: enabled)
        try reloadState()
    }

    func asset(_ path: String) -> URL? {
        Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "Media")
    }

    func deleteLocalProfile() throws {
        try library.delete()
        do { try wallet.purge() } catch {
            leave?()
            throw error
        }
        leave?()
    }
}

@main @MainActor final class VavaApplication: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var library: LocalLibrary?
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
                let library = try self.openLibrary()
                if try library.hasAccepted(Agreement.revision) { await enter(accepted: false) }
            } catch {
                ((window.rootViewController as? UINavigationController)?.viewControllers.first as? WelcomeScreen)?
                    .showError("Your local library could not be opened.")
            }
        }
        return true
    }

    private func openLibrary() throws -> LocalLibrary {
        if let library { return library }
        let opened = try LocalLibrary()
        library = opened
        return opened
    }

    private func showWelcome() {
        let welcome = WelcomeScreen()
        welcome.onContinue = { [weak self] in Task { await self?.enter(accepted: true) } }
        window?.rootViewController = UINavigationController(rootViewController: welcome)
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
                throw AppFailure("The bundled catalog could not be opened.")
            }
            let library = try openLibrary()
            let profile = try library.open(revision: Agreement.revision, accepted: accepted)
            let context = try AppContext(
                library: library, wallet: Wallet(account: profile.id), catalog: catalog)
            context.leave = { [weak self] in self?.showWelcome() }
            window?.rootViewController = Dock(context)
        } catch {
            welcome.showError(error.localizedDescription)
        }
    }
}

enum Agreement: String, CaseIterable {
    case terms = "Terms of Service"
    case privacy = "Privacy Policy"

    static let revision = "2026-11-13.2"
    var file: String { self == .terms ? "terms" : "privacy" }

    var bundledURL: URL? { Bundle.main.url(forResource: file, withExtension: "pdf") }
}

@MainActor final class AgreementScreen: UIViewController {
    let agreement: Agreement

    init(_ agreement: Agreement) {
        self.agreement = agreement
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.fill(view)
        let back = Theme.icon("back", label: "Back") { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        let title = Theme.label(agreement.rawValue, size: 25, display: true)
        let header = Theme.stack([back, title], axis: .horizontal)
        let pdf = PDFView()
        pdf.autoScales = true
        pdf.backgroundColor = Theme.ink
        if let local = agreement.bundledURL { pdf.document = PDFDocument(url: local) }
        let stack = Theme.stack([header, pdf])
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: safe.topAnchor),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
        ])
    }
}

@MainActor final class WelcomeScreen: UIViewController {
    var onContinue: (() -> Void)?
    private var accepted = false
    private let status = Theme.label("", color: Theme.coral)
    private let cover = UIImageView(image: UIImage(named: "welcome"))
    private lazy var accept = Theme.icon("check", label: "Accept the agreements") { [weak self] in
        guard let self else { return }
        self.accepted.toggle()
        self.updateCheckbox()
    }
    private lazy var enter = Theme.button("Continue", primary: true) { [weak self] in
        guard let self else { return }
        guard self.accepted else {
            self.showError("Accept the agreements to continue.")
            return
        }
        self.onContinue?()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        Theme.fill(view)
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 22
        cover.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let heading = Theme.label("Vava", size: 43, display: true)
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
                    self?.navigationController?.pushViewController(AgreementScreen(agreement), animated: true)
                }, for: .touchUpInside)
            return button
        }
        let links = Theme.stack(agreements, spacing: 10, axis: .horizontal)
        links.alignment = .leading
        let consent = Theme.stack(
            [accept, Theme.stack([Theme.label("I agree to the", size: 15), links], spacing: 0)],
            axis: .horizontal)
        consent.alignment = .center
        status.isHidden = true
        let content = Theme.stack([cover, heading, subtitle, consent, status, enter], spacing: 9)
        view.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -10),
        ])
        updateCheckbox()
    }

    private func updateCheckbox() {
        accept.layer.cornerRadius = 12
        accept.backgroundColor = accepted ? Theme.lime : Theme.panel
        accept.subviews.first?.alpha = accepted ? 1 : 0.24
        accept.accessibilityValue = accepted ? "Checked" : "Unchecked"
        accept.accessibilityTraits = accepted ? [.button, .selected] : [.button]
    }

    func setLoading(_ loading: Bool) {
        loadViewIfNeeded()
        enter.isEnabled = !loading
        enter.setTitle(loading ? "Opening…" : "Continue", for: .normal)
    }

    func showError(_ message: String) {
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
        let roots: [(String, String, UIViewController)] = [
            ("Shorts", "shorts", ShortsScreen(context)),
            ("Academy", "academy", AcademyScreen(context)),
            ("Watch", "watch", WatchScreen(context)),
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
