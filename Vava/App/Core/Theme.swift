import SafariServices
import UIKit

@MainActor enum Theme {
    static let ink = UIColor(red: 0.05, green: 0.13, blue: 0.12, alpha: 1)
    static let panel = UIColor(red: 0.10, green: 0.22, blue: 0.19, alpha: 1)
    static let line = UIColor(red: 0.27, green: 0.38, blue: 0.31, alpha: 1)
    static let ivory = UIColor(red: 1, green: 0.95, blue: 0.83, alpha: 1)
    static let secondary = UIColor(red: 0.78, green: 0.84, blue: 0.76, alpha: 1)
    static let lime = UIColor(red: 0.83, green: 0.94, blue: 0.48, alpha: 1)
    static let coral = UIColor(red: 1, green: 0.42, blue: 0.32, alpha: 1)

    static func font(_ size: CGFloat, display: Bool = false) -> UIFont {
        let name = display ? "Kalam-Bold" : "ComicNeue-Regular"
        guard let font = UIFont(name: name, size: size) else {
            return UIFont(descriptor: UIFontDescriptor(name: name, size: size), size: size)
        }
        return UIFontMetrics(forTextStyle: display ? .headline : .body).scaledFont(for: font)
    }

    static func label(
        _ text: String, size: CGFloat = 17, display: Bool = false,
        color: UIColor = Theme.ivory
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font(size, display: display)
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func stack(_ views: [UIView] = [], spacing: CGFloat = 12, axis: NSLayoutConstraint.Axis = .vertical)
        -> UIStackView
    {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.spacing = spacing
        return stack
    }

    static func button(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.setTitleColor(primary ? ink : ivory, for: .normal)
        button.setTitleColor(secondary.withAlphaComponent(0.55), for: .disabled)
        button.titleLabel?.font = font(17, display: true)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        button.backgroundColor = primary ? lime : panel
        button.layer.cornerRadius = 14
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func icon(_ name: String, label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = label
        let glyph = UIImageView(image: UIImage(named: "icon-" + name))
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        glyph.pin(to: button, top: 4, left: 4, bottom: 4, right: 4)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func field(_ placeholder: String, value: String? = nil) -> UITextField {
        let field = UITextField()
        field.text = value
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: secondary, .font: font(17),
            ])
        field.accessibilityLabel = placeholder
        field.font = font(17)
        field.textColor = ivory
        field.tintColor = lime
        field.backgroundColor = panel
        field.layer.cornerRadius = 14
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.clearButtonMode = .never
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        return field
    }

    static func photo(_ name: String? = nil, ratio: CGFloat = 0.52) -> UIImageView {
        let photo = UIImageView(image: name.flatMap { UIImage(named: $0) })
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.backgroundColor = panel
        photo.layer.cornerRadius = 16
        photo.heightAnchor.constraint(equalTo: photo.widthAnchor, multiplier: ratio).isActive = true
        return photo
    }

    static func fill(_ root: UIView, image: String = "background") {
        root.backgroundColor = ink
        let imageView = UIImageView(image: UIImage(named: image))
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.alpha = 0.62
        imageView.pin(to: root)
    }

    static func card(_ views: [UIView], spacing: CGFloat = 8) -> UIView {
        let surface = UIView()
        surface.backgroundColor = panel
        surface.layer.cornerRadius = 20
        surface.layer.borderWidth = 1
        surface.layer.borderColor = line.cgColor
        stack(views, spacing: spacing).pin(to: surface, top: 14, left: 14, bottom: 14, right: 14)
        return surface
    }
}

extension UIView {
    func pin(to view: UIView, top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        view.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: view.topAnchor, constant: top),
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: left),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -right),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottom),
        ])
    }
}

@MainActor class Screen: UIViewController {
    let context: AppContext

    init(_ context: AppContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.fill(view)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    func push(_ screen: UIViewController) { navigationController?.pushViewController(screen, animated: true) }

    func show(_ title: String, message: String) {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func confirm(
        _ title: String, message: String, action: String, destructive: Bool = false,
        perform: @escaping () -> Void
    ) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: action, style: destructive ? .destructive : .default) { _ in perform() })
        present(alert, animated: true)
    }

    func perform(_ action: @escaping () async throws -> Void) {
        Task { [weak self] in
            do { try await action() } catch is CancellationError {} catch {
                self?.show("Please try again", message: error.localizedDescription)
            }
        }
    }

    func open(_ url: URL) {
        guard url.scheme == "https" else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    func share(_ items: [Any], from source: UIView) {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = source
        present(activity, animated: true)
    }
}

@MainActor class ListScreen: Screen {
    let heading = Theme.label("", size: 35, display: true)
    let toolbar = Theme.stack(spacing: 2, axis: .horizontal)
    let scroll = UIScrollView()
    let body = Theme.stack(spacing: 12)
    private let refresh = UIRefreshControl()
    private var refreshing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let top = Theme.stack(spacing: 8, axis: .horizontal)
        top.alignment = .center
        if let nav = navigationController, nav.viewControllers.first !== self {
            top.addArrangedSubview(
                Theme.icon("back", label: "Back") { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                })
        }
        heading.accessibilityTraits.insert(.header)
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(heading)
        top.addArrangedSubview(toolbar)
        let safe = view.safeAreaLayoutGuide
        for item in [top, scroll] {
            view.addSubview(item)
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        scroll.addSubview(body)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            top.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -18),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36),
        ])
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        refresh.tintColor = Theme.lime
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        scroll.refreshControl = refresh
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let atRoot = navigationController?.viewControllers.first === self
        scroll.contentInset.bottom = atRoot ? 82 : 0
        scroll.verticalScrollIndicatorInsets.bottom = scroll.contentInset.bottom
    }

    @objc private func reload() {
        guard !refreshing else { return }
        refreshing = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.refreshing = false
                self.refresh.endRefreshing()
            }
            do { try await self.refreshContent() } catch {
                self.show("Could not refresh", message: error.localizedDescription)
            }
        }
    }

    func refreshContent() async throws {}
    func render(_ views: [UIView]) {
        for view in body.arrangedSubviews {
            body.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        views.forEach(body.addArrangedSubview)
    }
}

@MainActor final class PictureLoader {
    static let shared = PictureLoader()
    private let cache = NSCache<NSURL, UIImage>()

    func load(_ url: URL?, into view: UIImageView?, completion: ((UIImage) -> Void)? = nil) {
        guard let url, url.isFileURL else { return }
        if let cached = cache.object(forKey: url as NSURL) {
            view?.image = cached
            completion?(cached)
            return
        }
        guard let photo = UIImage(contentsOfFile: url.path) else { return }
        cache.setObject(photo, forKey: url as NSURL)
        view?.image = photo
        completion?(photo)
    }
}
