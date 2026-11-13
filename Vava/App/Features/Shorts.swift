import AVFoundation
import UIKit

private final class VideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var activate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        activate?() ?? false
    }
}

@MainActor final class ShortsScreen: Screen, UIGestureRecognizerDelegate {
    private let fixedClips: [Clip]?
    private var selectedID: String?
    private var queue: AVQueuePlayer?
    private var loop: AVPlayerLooper?
    private var playbackObservation: NSKeyValueObservation?
    private var feedIndex = 0
    private var clips: [Clip] = []
    private var dockOffset: CGFloat { fixedClips == nil ? 86 : 12 }
    private let poster = UIImageView()
    private let video = VideoSurface()
    private let pageView = UIView()
    private let adjacentPage = UIView()
    private let adjacentPoster = UIImageView()
    private lazy var paging = UIPanGestureRecognizer(target: self, action: #selector(dragPage(_:)))
    private var adjacentIndex: Int?
    private var settlingPage = false
    private let titleLabel = Theme.label("", size: 26, display: true)
    private let byline = Theme.label("", size: 16, color: Theme.lime)
    private let detail = Theme.label("", size: 16)
    private let position = Theme.label("", size: 14, color: Theme.secondary)
    private let failure = Theme.label("", color: Theme.coral)
    private let estimateLabel = Theme.label("Includes estimated activity", size: 12, color: Theme.secondary)
    private weak var feedControls: UIStackView?
    private let rail = Theme.stack(spacing: 1)
    private let heading = Theme.label("Shorts", size: 36, display: true)
    private let searchBox = Theme.stack(spacing: 0, axis: .horizontal)
    private let searchField = Theme.field("Find a player, rally or match")
    private let searchResults = UIScrollView()
    private let searchRows = Theme.stack(spacing: 12)
    private let searchShade = UIView()
    private let trailingAction = UIView()
    private var trailingWidth: NSLayoutConstraint?
    private var searchButton: UIButton?
    private var addButton: UIButton?
    private var closeSearchButton: UIButton?
    private var searchOpen = false
    private var savedOnly = false
    private var feedOrder = 0
    private var searchOrder = 0
    private let searchRefresh = UIRefreshControl()
    private var showingComments = false
    private var paused = false
    private var changing = false
    private var requestedSeek = false
    private var timeObserver: Any?
    private var visible = false
    private let progress = UISlider()
    private let topShade = CAGradientLayer()
    private let bottomShade = CAGradientLayer()

    init(_ context: AppContext, clips: [Clip]? = nil, selected: String? = nil) {
        fixedClips = clips
        selectedID = selected
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        view.clipsToBounds = true
        adjacentPage.backgroundColor = Theme.ink
        adjacentPage.isHidden = true
        adjacentPage.isUserInteractionEnabled = false
        adjacentPage.pin(to: view)
        adjacentPoster.contentMode = .scaleAspectFit
        adjacentPoster.pin(to: adjacentPage)
        pageView.backgroundColor = Theme.ink
        pageView.pin(to: view)
        poster.contentMode = .scaleAspectFit
        poster.pin(to: pageView)
        video.playerLayer.videoGravity = .resizeAspect
        video.pin(to: pageView)
        topShade.colors = [Theme.ink.cgColor, Theme.ink.withAlphaComponent(0).cgColor]
        bottomShade.colors = [Theme.ink.withAlphaComponent(0).cgColor, Theme.ink.cgColor]
        pageView.layer.addSublayer(topShade)
        pageView.layer.addSublayer(bottomShade)

        heading.accessibilityTraits.insert(.header)
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let top = Theme.stack(spacing: 4, axis: .horizontal)
        top.alignment = .center
        if fixedClips != nil {
            top.addArrangedSubview(
                Theme.icon("back", label: "Back") { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                })
        }
        top.addArrangedSubview(heading)
        configureSearch(in: top)
        let caption = Theme.stack([position, byline, titleLabel, detail, estimateLabel, failure], spacing: 3)
        titleLabel.numberOfLines = 2
        detail.numberOfLines = 2
        failure.isHidden = true
        let bottom = Theme.stack([caption, rail], spacing: 10, axis: .horizontal)
        bottom.alignment = .bottom
        estimateLabel.isHidden = true
        feedControls = bottom
        progress.minimumTrackTintColor = Theme.lime
        progress.maximumTrackTintColor = Theme.secondary.withAlphaComponent(0.25)
        progress.accessibilityLabel = "Playback position"
        progress.addAction(UIAction { [weak self] _ in self?.requestedSeek = true }, for: .touchDown)
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .valueChanged] {
            progress.addAction(UIAction { [weak self] _ in self?.seek() }, for: event)
        }
        let safe = view.safeAreaLayoutGuide
        view.addSubview(top)
        top.translatesAutoresizingMaskIntoConstraints = false
        for item in [bottom, progress] {
            pageView.addSubview(item)
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
            top.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            top.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            bottom.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            bottom.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -1),
            progress.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            progress.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -18),
            progress.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -dockOffset),
        ])
        installSearchResults(below: top)
        video.accessibilityTraits = .button
        video.activate = { [weak self] in
            guard let self, self.clip != nil else { return false }
            self.togglePlayback()
            return true
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(likeFromVideo))
        doubleTap.numberOfTapsRequired = 2
        video.addGestureRecognizer(tap)
        video.addGestureRecognizer(doubleTap)
        paging.delegate = self
        pageView.addGestureRecognizer(paging)
        tap.require(toFail: doubleTap)
        tap.require(toFail: paging)
        doubleTap.require(toFail: paging)
        NotificationCenter.default.addObserver(
            self, selector: #selector(inactive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(active), name: UIApplication.didBecomeActiveNotification, object: nil)
        syncClips()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if searchOpen,
            previousTraitCollection?.preferredContentSizeCategory
                != traitCollection.preferredContentSizeCategory
        {
            drawSearch()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        topShade.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 175)
        bottomShade.frame = CGRect(
            x: 0, y: view.bounds.height * 0.56, width: view.bounds.width, height: view.bounds.height * 0.44)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncClips()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        active()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard !showingComments else { return }
        searchField.resignFirstResponder()
        visible = false
        inactive()
    }

    deinit {
        if let timeObserver { queue?.removeTimeObserver(timeObserver) }
    }

    private var clip: Clip? { clips.indices.contains(feedIndex) ? clips[feedIndex] : nil }

    private func syncClips() {
        let prior = clip?.id
        let wanted = selectedID ?? prior
        clips = (fixedClips ?? context.catalog.shorts).filter { context.state.canShow($0) }
            .rotated(by: feedOrder)
        feedIndex =
            wanted.flatMap { id in clips.firstIndex { $0.id == id } } ?? min(feedIndex, max(0, clips.count - 1))
        selectedID = nil
        if prior != clip?.id || queue == nil { loadClip() } else { drawRail() }
        if searchOpen { drawSearch() }
    }

    private func loadClip() {
        inactive()
        if let timeObserver { queue?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playbackObservation = nil
        loop = nil
        queue = nil
        video.playerLayer.player = nil
        poster.image = nil
        progress.value = 0
        requestedSeek = false
        failure.isHidden = true
        estimateLabel.isHidden = clip?.submissionID != nil || clip == nil
        guard let clip else {
            titleLabel.text = "No clips available"
            byline.text = nil
            detail.text = "Swipe down to refresh."
            position.text = nil
            drawRail()
            return
        }
        titleLabel.text = clip.title
        byline.text = clip.publisher
        detail.text = clip.detail
        let indexText = "\(feedIndex + 1) of \(clips.count)"
        position.text = clip.duration > 0 ? "\(indexText)  ·  \(clip.duration)s" : indexText
        let expected = clip.id
        if !clip.cover.isEmpty {
            PictureLoader.shared.load(context.asset(clip.cover), into: nil) { [weak self] image in
                guard self?.clip?.id == expected else { return }
                self?.poster.image = image
            }
        }
        guard let url = try? context.videoURL(for: clip) else {
            failure.text = "This video is unavailable."
            failure.isHidden = false
            drawRail()
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        queue = player
        loop = AVPlayerLooper(player: player, templateItem: item)
        video.playerLayer.player = player
        playbackObservation = player.observe(\.currentItem?.status, options: [.initial, .new]) {
            [weak self, weak player] _, _ in
            Task { @MainActor in
                guard let self, let player, self.queue === player else { return }
                if player.currentItem?.status == .failed {
                    self.failure.text = "Playback failed. Tap the video to retry."
                    self.failure.isHidden = false
                    self.updatePlaybackAccessibility()
                }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.requestedSeek, !self.progress.isTracking,
                    let duration = self.queue?.currentItem?.duration.seconds, duration.isFinite, duration > 0
                else { return }
                self.progress.value = Float(time.seconds / duration)
            }
        }
        drawRail()
        active()
    }

    private func drawRail() {
        for button in rail.arrangedSubviews {
            rail.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        updatePlaybackAccessibility()
        guard let clip else { return }
        let ownWork = clip.submissionID != nil
        let avatar = UIButton(type: .custom)
        avatar.accessibilityLabel = ownWork ? "View your profile" : "View \(clip.publisher) profile"
        avatar.widthAnchor.constraint(equalToConstant: 46).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 46).isActive = true
        let portrait = Theme.avatar(
            38,
            photo: ownWork ? context.state.me.avatarJPEG.flatMap { UIImage(data: $0) } : nil,
            source: ownWork ? nil : context.portrait(for: clip.author))
        avatar.addSubview(portrait)
        portrait.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            portrait.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            portrait.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
        ])
        avatar.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                if ownWork {
                    self.navigationController?.popToRootViewController(animated: true)
                } else {
                    self.push(PublisherProfileScreen(self.context, publisher: clip.author))
                }
            }, for: .touchUpInside)
        rail.addArrangedSubview(avatar)
        let counts = context.state.engagement(for: clip)
        let liked = context.state.likes.contains(clip.id)
        let saved = context.state.saves.contains(clip.id)
        let like = metricButton(
            liked ? "like-selected" : "like-outline", label: liked ? "Unlike clip" : "Like clip",
            count: counts.likes, selected: liked
        ) { [weak self] _ in self?.change(clip, kind: .like, enabled: !liked) }
        let comment = metricButton("comment", label: "Comments", count: counts.comments) { [weak self] _ in
            self?.showComments(for: clip)
        }
        let save = metricButton(
            saved ? "save-selected" : "save-outline", label: saved ? "Remove saved clip" : "Save clip",
            count: counts.saves, selected: saved
        ) { [weak self] _ in self?.change(clip, kind: .save, enabled: !saved) }
        let shareButton = metricButton("share", label: "Share clip", count: counts.shares) {
            [weak self] source in
            self?.share(clip, from: source)
        }
        let more = Theme.icon("more", label: "More clip actions") {}
        more.showsMenuAsPrimaryAction = true
        var actions: [UIAction] = []
        if clip.source != nil {
            actions.append(
                UIAction(title: "Clip source and license") { [weak self] _ in
                    guard let self else { return }
                    self.push(ClipCreditsScreen(self.context, clip: clip))
                })
        }
        if clip.submissionID == nil {
            actions.append(
                UIAction(title: "Report clip", attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    self.reportContent(clip.id, title: "Report clip") { [weak self] in self?.syncClips() }
                })
            actions.append(
                UIAction(title: "Block publisher", attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    self.blockPublisher(clip.author) { [weak self] in self?.syncClips() }
                })
            actions.append(
                UIAction(title: "Hide clip", attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    self.push(
                        HideContentScreen(self.context, target: clip.id) { [weak self] in self?.syncClips()
                        })
                })
        }
        more.menu = UIMenu(children: actions)
        [like, comment, save, shareButton].forEach(rail.addArrangedSubview)
        if !actions.isEmpty { rail.addArrangedSubview(more) }
    }

    private func metricButton(
        _ icon: String, label: String, count: Int, selected: Bool = false,
        action: @escaping (UIButton) -> Void
    ) -> UIButton {
        let button = UIButton(type: .custom)
        button.widthAnchor.constraint(equalToConstant: 46).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        button.accessibilityLabel = label
        button.accessibilityValue = count.formatted()
        if selected { button.accessibilityTraits.insert(.selected) }
        let glyph = UIImageView(image: UIImage(named: "icon-" + icon))
        glyph.contentMode = .scaleAspectFit
        glyph.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let number = Theme.label(count.formatted(), size: 12, display: true)
        number.textAlignment = .center
        number.numberOfLines = 1
        number.adjustsFontSizeToFitWidth = true
        let content = Theme.stack([glyph, number], spacing: 0)
        content.isUserInteractionEnabled = false
        content.pin(to: button, top: 1, left: 1, bottom: 1, right: 1)
        button.addAction(
            UIAction { [weak button] _ in
                if let button { action(button) }
            }, for: .touchUpInside)
        return button
    }

    private func showComments(for clip: Clip) {
        guard presentedViewController == nil else { return }
        showingComments = true
        let sheet = DiscussionSheet(
            context, clip: clip, onChange: { [weak self] in self?.drawRail() },
            onClose: { [weak self] in
                self?.showingComments = false
                self?.active()
            })
        present(sheet, animated: false)
    }

    private func share(_ clip: Clip, from source: UIButton) {
        guard presentedViewController == nil else { return }
        guard let item = clip.source ?? (try? context.videoURL(for: clip)) else {
            show("Sharing unavailable", message: "This video is unavailable.")
            return
        }
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = source
        sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            Task { @MainActor in
                guard let self, completed else { return }
                self.perform {
                    try self.context.library.recordShare(clip.id)
                    try self.context.reloadState()
                    self.drawRail()
                }
            }
        }
        present(sheet, animated: true)
    }

    private func change(_ clip: Clip, kind: Activity, enabled: Bool) {
        guard !changing else { return }
        changing = true
        perform {
            defer { self.changing = false }
            try self.context.change(clip.id, kind: kind, enabled: enabled)
            self.drawRail()
        }
    }

    private func seek() {
        if let duration = queue?.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            queue?.seek(to: CMTime(seconds: Double(progress.value) * duration, preferredTimescale: 600))
        }
        requestedSeek = progress.isTracking
    }

    @objc private func togglePlayback() {
        guard clip != nil, !settlingPage, !searchOpen, !showingComments else { return }
        if !failure.isHidden {
            loadClip()
            return
        }
        guard queue != nil else { return }
        paused.toggle()
        if paused { inactive() } else { active() }
        updatePlaybackAccessibility()
    }

    @objc private func likeFromVideo() {
        guard !settlingPage, !searchOpen, !showingComments,
            let clip, !context.state.likes.contains(clip.id)
        else { return }
        change(clip, kind: .like, enabled: true)
    }

    private func updatePlaybackAccessibility() {
        video.isAccessibilityElement = clip != nil && !searchOpen
        video.accessibilityLabel = failure.isHidden ? (paused ? "Play video" : "Pause video") : "Retry video"
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === paging, !searchOpen, !showingComments, !settlingPage else { return false }
        let velocity = paging.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let item = target, item !== pageView {
            if item is UIControl { return false }
            target = item.superview
        }
        return true
    }

    @objc private func dragPage(_ gesture: UIPanGestureRecognizer) {
        let height = view.bounds.height
        guard height > 0 else { return }
        let offset = max(-height, min(height, gesture.translation(in: view).y))
        let next = feedIndex + (offset < 0 ? 1 : -1)
        switch gesture.state {
        case .changed:
            if clips.indices.contains(next), offset != 0 {
                if adjacentIndex != next {
                    adjacentIndex = next
                    adjacentPoster.image = nil
                    let adjacent = clips[next]
                    if !adjacent.cover.isEmpty {
                        PictureLoader.shared.load(context.asset(adjacent.cover), into: adjacentPoster)
                    } else if let url = try? context.videoURL(for: adjacent) {
                        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                        generator.appliesPreferredTrackTransform = true
                        generator.maximumSize = CGSize(width: 480, height: 720)
                        Task { @MainActor [weak self] in
                            guard let image = try? await generator.image(at: .zero),
                                let self, self.adjacentIndex == next,
                                self.clips.indices.contains(next), self.clips[next].id == adjacent.id
                            else { return }
                            self.adjacentPoster.image = UIImage(cgImage: image.image)
                        }
                    }
                }
                adjacentPage.isHidden = false
                adjacentPage.transform = CGAffineTransform(
                    translationX: 0, y: offset + (offset < 0 ? height : -height))
                pageView.transform = CGAffineTransform(translationX: 0, y: offset)
            } else {
                adjacentIndex = nil
                adjacentPage.isHidden = true
                pageView.transform = CGAffineTransform(translationX: 0, y: offset * 0.15)
            }
        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: view).y
            let flick = abs(offset) > 20 && abs(velocity) > 550 && offset * velocity > 0
            let commit =
                gesture.state == .ended && adjacentIndex == next
                && (abs(offset) > height * 0.20 || flick)
            let refresh = gesture.state == .ended && !commit && offset > 80 && feedIndex == 0
            settlePage(next: commit ? next : nil, direction: offset < 0 ? -1 : 1, refresh: refresh)
        default:
            break
        }
    }

    private func refreshFeed() {
        perform {
            try self.context.reload()
            let visible = (self.fixedClips ?? self.context.catalog.shorts).filter {
                self.context.state.canShow($0)
            }
            let refreshed = visible.rotated(by: self.feedOrder)
            if refreshed.count > 1 {
                let previous = self.clip?.id
                let current = refreshed.firstIndex { $0.id == previous } ?? -1
                self.feedOrder = (self.feedOrder + current + 1) % refreshed.count
                self.selectedID = visible[self.feedOrder].id
                self.paused = false
            }
            self.syncClips()
            self.refreshFeedback.show(in: self.view, message: "Feed updated")
        }
    }

    private func settlePage(next: Int?, direction: CGFloat, refresh: Bool) {
        settlingPage = true
        let height = view.bounds.height
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.0 : 0.24
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.pageView.transform =
                next == nil ? .identity : CGAffineTransform(translationX: 0, y: height * direction)
            self.adjacentPage.transform =
                next == nil
                ? CGAffineTransform(translationX: 0, y: -height * direction) : .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            let preview = self.adjacentPoster.image
            self.pageView.transform = .identity
            self.adjacentPage.isHidden = true
            self.adjacentPage.transform = .identity
            self.adjacentIndex = nil
            self.adjacentPoster.image = nil
            self.settlingPage = false
            if let next, self.clips.indices.contains(next) {
                self.feedIndex = next
                self.paused = false
                self.loadClip()
                if self.poster.image == nil { self.poster.image = preview }
            } else {
                self.active()
                if refresh { self.refreshFeed() }
            }
        }
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard !searchOpen, !showingComments, !settlingPage, direction == .up || direction == .down
        else { return super.accessibilityScroll(direction) }
        let next = feedIndex + (direction == .up ? 1 : -1)
        guard clips.indices.contains(next) else { return false }
        feedIndex = next
        paused = false
        loadClip()
        UIAccessibility.post(notification: .pageScrolled, argument: clip?.title)
        return true
    }

    @objc private func inactive() { queue?.pause() }

    @objc private func active() {
        guard !paused, visible, !settlingPage, viewIfLoaded?.window != nil,
            presentedViewController == nil || showingComments,
            UIApplication.shared.applicationState == .active,
            navigationController?.topViewController === self
        else { return }
        queue?.play()
    }

    private func configureSearch(in top: UIStackView) {
        let open = Theme.icon("search", label: "Search clips") { [weak self] in self?.setSearchOpen(true) }
        searchButton = open
        searchBox.alignment = .center
        searchBox.clipsToBounds = true
        searchBox.layer.cornerRadius = 14
        searchBox.addArrangedSubview(open)
        searchField.isHidden = true
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.addAction(UIAction { [weak self] _ in self?.drawSearch() }, for: .editingChanged)
        searchField.addAction(
            UIAction { [weak self] _ in self?.searchField.resignFirstResponder() }, for: .editingDidEndOnExit)
        searchBox.addArrangedSubview(searchField)
        top.addArrangedSubview(searchBox)

        let close = Theme.icon("close", label: "Close search") { [weak self] in self?.setSearchOpen(false) }
        closeSearchButton = close
        close.isHidden = true
        let add = Theme.icon("add", label: "Add a video") { [weak self] in
            guard let self else { return }
            self.push(SubmissionScreen(self.context))
        }
        addButton = add
        add.isHidden = fixedClips != nil
        for button in [add, close] {
            trailingAction.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: trailingAction.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: trailingAction.centerYAnchor),
            ])
        }
        let width = trailingAction.widthAnchor.constraint(equalToConstant: fixedClips == nil ? 44 : 0)
        trailingWidth = width
        NSLayoutConstraint.activate([width, trailingAction.heightAnchor.constraint(equalToConstant: 44)])
        top.addArrangedSubview(trailingAction)
    }

    private func installSearchResults(below top: UIView) {
        searchShade.backgroundColor = Theme.ink.withAlphaComponent(0.84)
        searchShade.alpha = 0
        searchShade.isHidden = true
        searchShade.pin(to: view)
        searchResults.alpha = 0
        searchResults.isHidden = true
        searchResults.keyboardDismissMode = .onDrag
        searchResults.alwaysBounceVertical = true
        searchRefresh.tintColor = Theme.lime
        searchRefresh.addTarget(self, action: #selector(refreshSearch), for: .valueChanged)
        searchResults.refreshControl = searchRefresh
        view.addSubview(searchResults)
        searchResults.translatesAutoresizingMaskIntoConstraints = false
        searchRows.pin(to: searchResults, top: 8, left: 18, bottom: 16, right: 18)
        let keyboardBottom = searchResults.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        keyboardBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            searchResults.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            searchResults.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            searchResults.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            searchResults.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -dockOffset),
            keyboardBottom,
            searchRows.widthAnchor.constraint(
                equalTo: searchResults.frameLayoutGuide.widthAnchor, constant: -36),
        ])
        view.bringSubviewToFront(top)
    }

    private func setSearchOpen(_ open: Bool) {
        guard searchOpen != open else { return }
        searchOpen = open
        if open {
            searchShade.isHidden = false
            searchResults.isHidden = false
            drawSearch()
        } else {
            searchField.resignFirstResponder()
        }
        searchButton?.isEnabled = !open
        paging.isEnabled = !open
        updatePlaybackAccessibility()
        progress.isAccessibilityElement = !open
        feedControls?.accessibilityElementsHidden = open
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.0 : 0.24
        UIView.animate(
            withDuration: duration,
            animations: {
                self.heading.isHidden = open
                self.searchField.isHidden = !open
                self.searchBox.backgroundColor = open ? Theme.panel : .clear
                self.addButton?.isHidden = open || self.fixedClips != nil
                self.closeSearchButton?.isHidden = !open
                self.trailingWidth?.constant = open || self.fixedClips == nil ? 44 : 0
                self.searchShade.alpha = open ? 1 : 0
                self.searchResults.alpha = open ? 1 : 0
                self.view.layoutIfNeeded()
            },
            completion: { [weak self] _ in
                guard let self, self.searchOpen == open else { return }
                self.searchShade.isHidden = !open
                self.searchResults.isHidden = !open
                if open, self.visible, self.view.window != nil {
                    self.searchField.becomeFirstResponder()
                }
            })
    }

    @objc private func refreshSearch() {
        defer { searchRefresh.endRefreshing() }
        do {
            try context.reload()
            searchOrder += 1
            syncClips()
            refreshFeedback.show(in: view, message: "Results updated")
        } catch {
            show("Could not refresh results", message: "Pull down to try again.")
        }
    }

    private func drawSearch() {
        let term = searchField.text?.trimmed ?? ""
        let matches = clips.filter { clip in
            (!savedOnly || context.state.saves.contains(clip.id))
                && (term.isEmpty
                    || "\(clip.title) \(clip.publisher) \(clip.detail)".localizedCaseInsensitiveContains(term))
        }
        for row in searchRows.arrangedSubviews { row.removeFromSuperview() }
        let all = Theme.button("All clips", primary: !savedOnly) { [weak self] in
            self?.savedOnly = false
            self?.drawSearch()
        }
        let saved = Theme.button("Saved", primary: savedOnly) { [weak self] in
            self?.savedOnly = true
            self?.drawSearch()
        }
        (savedOnly ? saved : all).accessibilityTraits.insert(.selected)
        let scope = Theme.stack([all, saved], spacing: 8, axis: .horizontal)
        scope.distribution = .fillEqually
        searchRows.addArrangedSubview(scope)
        if matches.isEmpty {
            searchRows.addArrangedSubview(
                Theme.card([
                    Theme.label(
                        term.isEmpty && savedOnly ? "No saved clips yet." : "No matching clips.")
                ]))
        }
        guard !matches.isEmpty else { return }
        let grid = ClipGrid.make(matches.rotated(by: searchOrder), context: context, traits: traitCollection) {
            [weak self] clip in
            guard let self, let index = self.clips.firstIndex(where: { $0.id == clip.id }) else { return }
            self.setSearchOpen(false)
            if self.feedIndex != index {
                self.feedIndex = index
                self.paused = false
                self.loadClip()
            }
        }
        searchRows.addArrangedSubview(grid)
    }
}

@MainActor final class ClipCreditsScreen: ListScreen {
    private let clip: Clip

    init(_ context: AppContext, clip: Clip) {
        self.clip = clip
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Source credit"
        let image = Theme.photo()
        PictureLoader.shared.load(context.asset(clip.cover), into: image)
        render([
            image, Theme.label(clip.publisher, size: 27, display: true),
            Theme.label(clip.title), Theme.label(clip.license, color: Theme.lime),
            Theme.label("Adapted for iPhone playback. The source page identifies the original recording."),
            Theme.button("Open original recording") { [weak self] in
                guard let self, let source = self.clip.source else { return }
                self.open(source)
            },
            Theme.button("View license") { [weak self] in
                guard let self, let license = self.clip.licenseURL else { return }
                self.open(license)
            },
        ])
    }
}
