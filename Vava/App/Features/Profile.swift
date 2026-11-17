import AVFoundation
import PhotosUI
import UIKit

@MainActor final class ProfileScreen: ListScreen, UIGestureRecognizerDelegate {
    private enum Collection: String, CaseIterable {
        case shorts = "Shorts"
        case tutorials = "Tutorials"
        case liked = "Liked"
        case saved = "Saved"
    }

    private var selection = Collection.shorts
    private var submissions: [Submission] = []
    private let collectionPage = UIView()
    private let collectionContent = Theme.stack()
    private lazy var collectionBar = ProfileCollectionBar(Collection.allCases.map(\.rawValue)) {
        [weak self] index in
        self?.selectCollection(at: index)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Me"
        NotificationCenter.default.addObserver(
            self, selector: #selector(walletChanged), name: .walletChanged, object: context.wallet)
        toolbar.addArrangedSubview(
            Theme.icon("settings", label: "Settings") { [weak self] in
                guard let self else { return }
                self.push(SettingsScreen(self.context))
            })
        configureCollectionPage()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
        perform { try await self.refreshContent() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded,
            previousTraitCollection?.preferredContentSizeCategory
                != traitCollection.preferredContentSizeCategory
        {
            draw()
        }
    }

    override func refreshContent() async throws {
        try context.reload()
        submissions = try context.library.submissions()
        draw()
    }

    @objc private func walletChanged() { draw() }

    private func draw() {
        let profile = context.state.me
        let works = context.ownedClips(from: submissions)
        let totals = context.state.totals(for: works)
        let summary = ProfileHeader.card(
            name: profile.name, bio: profile.bio.isEmpty ? "Add a bio in Settings." : profile.bio,
            photo: profile.avatarJPEG.flatMap { UIImage(data: $0) },
            counts: [
                ("Likes", totals.likes), ("Saves", totals.saves),
                ("Following", context.state.following.count),
            ])
        let wallet = Theme.button(
            "Wallet  ·  \(context.wallet.ledger.balance.formatted()) coins", primary: true
        ) { [weak self] in
            guard let self else { return }
            self.push(WalletScreen(self.context))
        }
        var views = [summary, wallet]
        if context.wallet.hasPurchaseIssue {
            views.append(
                Theme.label(
                    "Some purchases could not be added to your wallet. Open Wallet to retry.",
                    color: Theme.coral))
        }
        views += [collectionBar, collectionPage]
        render(views)
        drawCollection()
    }

    private func configureCollectionPage() {
        collectionPage.clipsToBounds = true
        collectionPage.addSubview(collectionContent)
        collectionContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionContent.topAnchor.constraint(equalTo: collectionPage.topAnchor),
            collectionContent.leadingAnchor.constraint(equalTo: collectionPage.leadingAnchor),
            collectionContent.trailingAnchor.constraint(equalTo: collectionPage.trailingAnchor),
            collectionContent.bottomAnchor.constraint(lessThanOrEqualTo: collectionPage.bottomAnchor),
            collectionPage.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(pageCollection(_:)))
        swipe.maximumNumberOfTouches = 1
        swipe.delegate = self
        collectionPage.addGestureRecognizer(swipe)
        scroll.panGestureRecognizer.require(toFail: swipe)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: collectionPage)
        return abs(velocity.x) > abs(velocity.y) * 1.4
    }

    @objc private func pageCollection(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let distance = pan.translation(in: collectionPage).x
        let velocity = pan.velocity(in: collectionPage).x
        guard abs(distance) >= 44 || (abs(distance) >= 14 && abs(velocity) >= 350) else { return }
        selectCollection(at: collectionBar.selectedIndex + (distance < 0 ? 1 : -1))
    }

    private func selectCollection(at index: Int) {
        let categories = Collection.allCases
        guard categories.indices.contains(index), categories[index] != selection else { return }
        if !UIAccessibility.isReduceMotionEnabled {
            let slide = CATransition()
            slide.type = .push
            slide.subtype = index > collectionBar.selectedIndex ? .fromRight : .fromLeft
            slide.duration = 0.22
            collectionPage.layer.add(slide, forKey: "collectionPage")
        }
        selection = categories[index]
        drawCollection()
    }

    private func drawCollection() {
        collectionBar.select(Collection.allCases.firstIndex(of: selection) ?? 0)
        var views: [UIView] = []
        switch selection {
        case .shorts:
            let works = context.ownedClips(from: submissions)
            views.append(
                Theme.button("Add a video") { [weak self] in
                    guard let self else { return }
                    self.push(SubmissionScreen(self.context))
                })
            if submissions.isEmpty {
                views.append(Theme.label("No works yet.", color: Theme.secondary))
            }
            views += clipRows(works.rotated(by: refreshOrder))
            if !submissions.isEmpty {
                let manage = Theme.button("Manage works") {}
                manage.showsMenuAsPrimaryAction = true
                manage.menu = UIMenu(
                    children: submissions.map { submission in
                        UIAction(title: "Remove \(submission.title)", attributes: .destructive) {
                            [weak self] _ in
                            self?.remove(submission)
                        }
                    })
                views.append(manage)
            }
        case .liked:
            let clips = clips(with: context.state.likes).rotated(by: refreshOrder)
            views +=
                clips.isEmpty ? [Theme.label("No liked clips yet.", color: Theme.secondary)] : clipRows(clips)
        case .saved:
            let savedClips = clips(with: context.state.saves).rotated(by: refreshOrder)
            var savedViews = clipRows(savedClips)
            for replay in context.catalog.replays
            where context.state.saves.contains(replay.id) && !context.state.hidden.contains(replay.id) {
                savedViews.append(
                    Theme.button(replay.title) { [weak self] in
                        guard let self else { return }
                        self.push(ReplayScreen(self.context, replay: replay))
                    })
            }
            for course in context.catalog.courses
            where context.state.saves.contains(course.id) && context.state.canShow(course) {
                savedViews.append(courseRow(course))
            }
            views +=
                savedViews.isEmpty
                ? [Theme.label("No saved items yet.", color: Theme.secondary)]
                : savedViews.rotated(by: refreshOrder)
        case .tutorials:
            views.append(Theme.label("My learning", size: 22, display: true))
            let courses = context.catalog.courses.filter {
                context.state.canShow($0)
                    && (context.wallet.ledger.owned.contains($0.id)
                        || !(context.state.practice[$0.id] ?? []).isEmpty)
            }
            if courses.isEmpty {
                views.append(
                    Theme.label(
                        "Start a lesson or unlock a practice plan to see it here.", color: Theme.secondary))
            } else {
                views += courses.rotated(by: refreshOrder).map(courseRow)
            }
        }
        for view in collectionContent.arrangedSubviews {
            view.removeFromSuperview()
        }
        views.forEach(collectionContent.addArrangedSubview)
    }

    private func clips(with ids: Set<String>) -> [Clip] {
        (context.catalog.shorts + context.ownedClips(from: submissions))
            .filter { ids.contains($0.id) && context.state.canShow($0) }
    }

    private func clipRows(_ clips: [Clip]) -> [UIView] {
        guard !clips.isEmpty else { return [] }
        return [
            ClipGrid.make(clips, context: context, traits: traitCollection) { [weak self] clip in
                guard let self else { return }
                self.push(ShortsScreen(self.context, clips: clips, selected: clip.id))
            }
        ]
    }

    private func courseRow(_ course: Course) -> UIView {
        let count = context.state.practice[course.id]?.count ?? 0
        let drills = count == 1 ? "drill" : "drills"
        return Theme.button("\(course.title)  ·  \(count) \(drills) complete") { [weak self] in
            guard let self else { return }
            self.push(CourseScreen(self.context, course: course))
        }
    }

    private func remove(_ submission: Submission) {
        confirm(
            "Remove this video?", message: "The original stays in Photos.",
            action: "Remove", destructive: true
        ) { [weak self] in
            guard let self else { return }
            self.perform {
                try self.context.library.removeVideo(submission)
                try await self.refreshContent()
            }
        }
    }
}

@MainActor private enum ProfileHeader {
    static func card(
        name: String, bio: String, photo: UIImage? = nil, cover: URL? = nil, counts: [(String, Int)]
    ) -> UIView {
        Theme.card(
            [identity(name: name, bio: bio, photo: photo, cover: cover), divider(), metrics(counts)],
            spacing: 12)
    }

    private static func identity(name: String, bio: String, photo: UIImage?, cover: URL?) -> UIView {
        let avatar = Theme.avatar(58, photo: photo, source: cover)
        let title = Theme.label(name, size: 26, display: true)
        title.accessibilityTraits.insert(.header)
        let details = Theme.stack([title, Theme.label(bio, size: 16, color: Theme.secondary)], spacing: 4)
        let identity = Theme.stack([avatar, details], spacing: 12, axis: .horizontal)
        identity.alignment = .center
        return identity
    }

    private static func metrics(_ values: [(String, Int)]) -> UIView {
        let columns = values.map { title, value in
            let number = Theme.label(value.formatted(), size: 23, display: true, color: Theme.lime)
            let label = Theme.label(title, size: 14, color: Theme.secondary)
            for text in [number, label] {
                text.textAlignment = .center
                text.numberOfLines = 1
                text.adjustsFontSizeToFitWidth = true
            }
            let column = Theme.stack([number, label], spacing: 1)
            column.isAccessibilityElement = true
            column.accessibilityLabel = title
            column.accessibilityValue = value.formatted()
            return column
        }
        let row = Theme.stack(columns, spacing: 4, axis: .horizontal)
        row.distribution = .fillEqually
        return row
    }

    static func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = Theme.line
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }
}

@MainActor private final class ProfileCollectionBar: UIView {
    private var tabs: [(control: UIButton, label: UILabel, indicator: UIView)] = []
    private(set) var selectedIndex = 0

    init(_ titles: [String], onSelect: @escaping (Int) -> Void) {
        super.init(frame: .zero)
        let row = Theme.stack(spacing: 2, axis: .horizontal)
        row.distribution = .fillEqually
        row.semanticContentAttribute = .forceLeftToRight
        Theme.stack([row, ProfileHeader.divider()], spacing: 0).pin(to: self)

        for (index, title) in titles.enumerated() {
            let control = UIButton(type: .custom)
            control.accessibilityLabel = title
            let label = Theme.label(title, size: 16, display: true)
            label.numberOfLines = 1
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            label.pin(to: control, left: 3, bottom: 3, right: 3)

            let indicator = UIView()
            indicator.backgroundColor = Theme.lime
            indicator.isUserInteractionEnabled = false
            control.addSubview(indicator)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                indicator.centerXAnchor.constraint(equalTo: control.centerXAnchor),
                indicator.bottomAnchor.constraint(equalTo: control.bottomAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 26),
                indicator.heightAnchor.constraint(equalToConstant: 3),
            ])
            control.addAction(UIAction { _ in onSelect(index) }, for: .touchUpInside)
            row.addArrangedSubview(control)
            tabs.append((control, label, indicator))
        }
        select(0)
    }

    required init?(coder: NSCoder) { nil }

    func select(_ index: Int) {
        selectedIndex = index
        for (position, tab) in tabs.enumerated() {
            let selected = position == index
            tab.label.textColor = selected ? Theme.lime : Theme.secondary
            tab.indicator.isHidden = !selected
            tab.control.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }
}

@MainActor enum ClipGrid {
    static func make(
        _ clips: [Clip], context: AppContext, traits: UITraitCollection,
        select: @escaping (Clip) -> Void
    ) -> UIView {
        let grid = Theme.stack(spacing: 10)
        let columns = traits.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 2
        for start in stride(from: 0, to: clips.count, by: columns) {
            let row = Theme.stack(spacing: 10, axis: .horizontal)
            row.alignment = .top
            row.distribution = .fillEqually
            for clip in clips[start..<min(start + columns, clips.count)] {
                let button = UIButton(type: .custom)
                button.accessibilityLabel = clip.title
                button.accessibilityHint = "Plays the clip"
                let image = Theme.photo(ratio: 0.72)
                if clip.submissionID != nil, let url = try? context.videoURL(for: clip) {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 420, height: 420)
                    Task { @MainActor [weak image] in
                        if let result = try? await generator.image(at: .zero) {
                            image?.image = UIImage(cgImage: result.image)
                        }
                    }
                } else {
                    PictureLoader.shared.load(context.asset(clip.cover), into: image)
                }
                let counts = context.state.engagement(for: clip)
                let tile = Theme.card(
                    [
                        image, Theme.label(clip.title, size: 17, display: true),
                        Theme.label(
                            "\(counts.likes.formatted()) likes · \(counts.saves.formatted()) saves", size: 13,
                            color: Theme.secondary),
                    ], spacing: 6)
                tile.isUserInteractionEnabled = false
                tile.pin(to: button)
                button.accessibilityValue =
                    "\(counts.likes.formatted()) likes, \(counts.saves.formatted()) saves"
                button.addAction(UIAction { _ in select(clip) }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            if row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
            grid.addArrangedSubview(row)
        }
        return grid
    }
}

@MainActor final class PublisherProfileScreen: ListScreen {
    private enum Works: String, CaseIterable {
        case shorts = "Shorts"
        case tutorials = "Tutorials"
    }

    private let publisher: Publisher
    private var selection: Works
    private lazy var worksBar = ProfileCollectionBar(Works.allCases.map(\.rawValue)) {
        [weak self] index in
        guard let self else { return }
        self.selection = Works.allCases[index]
        self.draw()
    }
    private lazy var reportButton = Theme.icon("report", label: "Report content") { [weak self] in
        self?.reportSingleWork()
    }

    init(_ context: AppContext, publisher: Publisher, openTutorials: Bool = false) {
        self.publisher = publisher
        selection = openTutorials ? .tutorials : .shorts
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Publisher"
        toolbar.addArrangedSubview(reportButton)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded,
            previousTraitCollection?.preferredContentSizeCategory
                != traitCollection.preferredContentSizeCategory
        {
            draw()
        }
    }

    override func refreshContent() async throws {
        try context.reload()
        draw()
    }

    private func draw() {
        let id = publisher.id
        let blocked = context.state.blocked.contains(id)
        let following = context.state.following.contains(id)
        let works = context.catalog.shorts.filter { $0.publisherID == id }
        let total = context.state.totals(for: works)
        let courses = context.catalog.courses.filter { $0.author.id == id }
        configureReportButton()
        let summary = ProfileHeader.card(
            name: publisher.name,
            bio: courses.isEmpty ? "Recording source" : "Coaching reference",
            cover: context.portrait(for: publisher),
            counts: [
                ("Likes", total.likes), ("Saves", total.saves), ("Your follows", following ? 1 : 0),
            ])
        let follow = Theme.button(following ? "Following" : "Follow", primary: !following) { [weak self] in
            guard let self else { return }
            self.update { try self.context.library.setFollowing(id, enabled: !following) }
        }
        follow.isEnabled = !blocked
        if following {
            follow.accessibilityTraits.insert(.selected)
            outline(follow, color: Theme.lime)
            follow.setTitleColor(Theme.lime, for: .normal)
        }
        let message = Theme.button("Message") { [weak self] in
            guard let self else { return }
            self.openChat(with: ChatPerson(self.publisher))
        }
        message.isEnabled = !blocked
        outline(message, color: Theme.line)
        let block = Theme.button(blocked ? "Unblock" : "Block") { [weak self] in
            self?.changeBlock()
        }
        block.backgroundColor = .clear
        block.setTitleColor(Theme.coral, for: .normal)
        let actionAxis: NSLayoutConstraint.Axis =
            traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        let actions = Theme.stack(
            [follow, message, block], spacing: 8, axis: actionAxis
        )
        if actionAxis == .horizontal {
            follow.widthAnchor.constraint(equalTo: message.widthAnchor).isActive = true
            block.setContentHuggingPriority(.required, for: .horizontal)
        }
        var views = [summary]
        if !works.isEmpty {
            views.append(Theme.label("Includes estimated activity", size: 12, color: Theme.secondary))
        }
        views.append(actions)
        if let website = publisher.website {
            views.append(Theme.button("Open source website") { [weak self] in self?.open(website) })
        }
        worksBar.select(Works.allCases.firstIndex(of: selection) ?? 0)
        views.append(worksBar)
        if blocked {
            views.append(
                Theme.label("Works are hidden while this publisher is blocked.", color: Theme.secondary))
        } else if selection == .shorts {
            let visibleWorks = works.filter { context.state.canShow($0) }.rotated(by: refreshOrder)
            if visibleWorks.isEmpty {
                views.append(Theme.label("No shorts to show.", color: Theme.secondary))
            } else {
                views.append(
                    ClipGrid.make(visibleWorks, context: context, traits: traitCollection) { [weak self] item in
                        guard let self else { return }
                        self.push(ShortsScreen(self.context, clips: visibleWorks, selected: item.id))
                    })
            }
        } else {
            let visibleCourses = courses.filter { context.state.canShow($0) }
            if visibleCourses.isEmpty {
                views.append(Theme.label("No tutorials to show.", color: Theme.secondary))
            }
            for course in visibleCourses.rotated(by: refreshOrder) {
                views.append(
                    Theme.button(course.title) { [weak self] in
                        guard let self else { return }
                        self.push(CourseScreen(self.context, course: course))
                    })
            }
        }
        if publisher.id == "table-tennis-england" {
            views.append(
                Theme.button("Team photo credit") { [weak self] in
                    guard
                        let url = URL(
                            string:
                                "https://commons.wikimedia.org/wiki/File:20220814_ECM22_Table_Tennis_8658.jpg")
                    else { return }
                    self?.open(url)
                })
            views.append(
                Theme.label(
                    "Tin-Tin Ho representing England · Ailura · CC BY-SA 3.0 AT · Cropped", size: 13,
                    color: Theme.secondary))
        }
        render(views)
    }

    private func outline(_ button: UIButton, color: UIColor) {
        button.backgroundColor = .clear
        button.layer.borderWidth = 1
        button.layer.borderColor = color.cgColor
    }

    private var reportableWorks: [(id: String, title: String)] {
        let clips = context.catalog.shorts.filter { $0.publisherID == publisher.id }.map { ($0.id, $0.title) }
        let courses = context.catalog.courses.filter { $0.author.id == publisher.id }.map { ($0.id, $0.title) }
        return (clips + courses).filter { !context.state.hidden.contains($0.0) }
    }

    private func configureReportButton() {
        let items = reportableWorks
        reportButton.isEnabled = !items.isEmpty
        reportButton.alpha = items.isEmpty ? 0.45 : 1
        reportButton.showsMenuAsPrimaryAction = items.count > 1
        reportButton.menu =
            items.count > 1
            ? UIMenu(
                title: "Choose content to report",
                children: items.map { item in
                    UIAction(title: item.title) { [weak self] _ in
                        self?.reportWork(item.id, title: item.title)
                    }
                })
            : nil
    }

    private func reportSingleWork() {
        let items = reportableWorks
        guard items.count == 1, let item = items.first else { return }
        reportWork(item.id, title: item.title)
    }

    private func reportWork(_ id: String, title: String) {
        reportContent(id, title: "Report \(title)") { [weak self] in self?.draw() }
    }

    private func changeBlock() {
        if context.state.blocked.contains(publisher.id) {
            update { try self.context.setBlocked(self.publisher, enabled: false) }
        } else {
            blockPublisher(publisher) { [weak self] in self?.draw() }
        }
    }

    private func update(_ change: @escaping () throws -> Void) {
        perform {
            try change()
            try await self.refreshContent()
        }
    }
}

@MainActor final class BlockedPublishersScreen: ListScreen {
    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Blocked publishers"
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
        let publishers = context.publishers.filter { context.state.blocked.contains($0.id) }
        if publishers.isEmpty {
            render([Theme.label("No publishers are blocked.", color: Theme.secondary)])
            return
        }
        render(
            publishers.rotated(by: refreshOrder).map { publisher in
                Theme.button(publisher.name) { [weak self] in
                    guard let self else { return }
                    self.push(PublisherProfileScreen(self.context, publisher: publisher))
                }
            })
    }
}

@MainActor final class SettingsScreen: ListScreen {

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Settings"
        let agreementButtons = Agreement.allCases.map { agreement in
            Theme.button(agreement.rawValue) { [weak self] in
                guard let self else { return }
                agreement.open(from: self)
            }
        }
        let edit = Theme.button("Edit profile") { [weak self] in
            guard let self else { return }
            self.push(EditProfileScreen(self.context))
        }
        let credits = Theme.button("Media credits") { [weak self] in
            guard let self else { return }
            self.push(CreditsScreen(self.context))
        }
        let blocked = Theme.button("Blocked publishers") { [weak self] in
            guard let self else { return }
            self.push(BlockedPublishersScreen(self.context))
        }
        let signOut = Theme.button("Log out") { [weak self] in self?.signOut() }
        let delete = Theme.button("Delete account") { [weak self] in self?.deleteAccount() }
        delete.setTitleColor(Theme.coral, for: .normal)
        render([edit, credits, blocked] + agreementButtons + [signOut, delete])
    }

    private func signOut() {
        confirm(
            "Log out?", message: "You can log back in to access your profile, saved activity, and wallet.",
            action: "Log out"
        ) { [weak self] in
            guard let self else { return }
            self.perform { try self.context.signOut() }
        }
    }

    private func deleteAccount() {
        confirm(
            "Delete account?",
            message:
                "This permanently deletes your profile, saved activity, imported copies, coins, and course access in Vava. Your original videos stay in Photos.",
            action: "Delete account", destructive: true
        ) { [weak self] in
            guard let self else { return }
            self.perform { try self.context.deleteAccount() }
        }
    }

}

@MainActor final class EditProfileScreen: ListScreen, PHPickerViewControllerDelegate {
    private lazy var name = Theme.field("Display name", value: context.state.me.name)
    private lazy var biography = Theme.field("Bio", value: context.state.me.bio)
    private var saving = false
    private var choosingPhoto = false
    private lazy var avatarJPEG = context.state.me.avatarJPEG
    private let photo = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Edit profile"
        photo.contentMode = .scaleAspectFit
        photo.heightAnchor.constraint(equalToConstant: 72).isActive = true
        photo.image = avatarJPEG.flatMap { UIImage(data: $0) } ?? UIImage(named: "icon-me")
        render([
            photo, Theme.button("Choose profile photo") { [weak self] in self?.choosePhoto() },
            name, biography, Theme.button("Save profile", primary: true) { [weak self] in self?.save() },
        ])
    }

    private func choosePhoto() {
        guard !choosingPhoto, !saving else { return }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        choosingPhoto = true
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            Task { @MainActor in
                guard let self else { return }
                self.choosingPhoto = false
                guard let image = object as? UIImage, min(image.size.width, image.size.height) > 0 else {
                    self.show("Photo could not be opened", message: "Choose another photo from Photos.")
                    return
                }
                let side: CGFloat = 256
                let scale = side / min(image.size.width, image.size.height)
                let width = image.size.width * scale
                let height = image.size.height * scale
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
                self.avatarJPEG = renderer.jpegData(withCompressionQuality: 0.85) { _ in
                    image.draw(
                        in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
                }
                self.photo.image = self.avatarJPEG.flatMap { UIImage(data: $0) }
            }
        }
    }

    private func save() {
        guard !saving, !choosingPhoto else { return }
        let name = self.name.text?.trimmed ?? ""
        let bio = biography.text?.trimmed ?? ""
        guard (1...40).contains(name.count), bio.count <= 180 else {
            show("Check your profile", message: "Use 1–40 characters for your name and up to 180 for your bio.")
            return
        }
        saving = true
        perform {
            defer { self.saving = false }
            try self.context.library.editProfile(name: name, bio: bio, avatarJPEG: self.avatarJPEG)
            try self.context.reloadState()
            self.navigationController?.popViewController(animated: true)
        }
    }
}

@MainActor final class CreditsScreen: ListScreen {
    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Media credits"
        draw()
    }

    override func refreshContent() async throws {
        try await super.refreshContent()
        draw()
    }

    private func draw() {
        let clips = context.catalog.shorts.map { clip in
            Theme.button("\(clip.title)  ·  \(clip.publisher)") { [weak self] in
                guard let self else { return }
                self.push(ClipCreditsScreen(self.context, clip: clip))
            }
        }
        let replays = context.catalog.replays.map { replay in
            Theme.button("\(replay.title)  ·  \(replay.publisher)") { [weak self] in self?.open(replay.source) }
        }
        render((clips + replays).rotated(by: refreshOrder))
    }
}
