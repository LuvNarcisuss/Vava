import AVFoundation
import UIKit

private final class VideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

@MainActor final class ShortsScreen: Screen {
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
    private let titleLabel = Theme.label("", size: 26, display: true)
    private let byline = Theme.label("", size: 16, color: Theme.lime)
    private let detail = Theme.label("", size: 16)
    private let position = Theme.label("", size: 14, color: Theme.secondary)
    private let failure = Theme.label("", color: Theme.coral)
    private let rail = Theme.stack(spacing: 3)
    private var paused = false
    private var muted = false
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
        poster.contentMode = .scaleAspectFit
        poster.pin(to: view)
        video.playerLayer.videoGravity = .resizeAspect
        video.pin(to: view)
        topShade.colors = [Theme.ink.cgColor, Theme.ink.withAlphaComponent(0).cgColor]
        bottomShade.colors = [Theme.ink.withAlphaComponent(0).cgColor, Theme.ink.cgColor]
        view.layer.addSublayer(topShade)
        view.layer.addSublayer(bottomShade)

        let heading = Theme.label("Shorts", size: 36, display: true)
        heading.accessibilityTraits.insert(.header)
        let top = Theme.stack(spacing: 4, axis: .horizontal)
        top.alignment = .center
        if fixedClips != nil {
            top.addArrangedSubview(
                Theme.icon("back", label: "Back") { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                })
        }
        top.addArrangedSubview(heading)
        top.addArrangedSubview(
            Theme.icon("search", label: "Search clips") { [weak self] in
                guard let self else { return }
                self.push(ClipSearchScreen(self.context))
            })
        if fixedClips == nil {
            top.addArrangedSubview(
                Theme.icon("add", label: "Add a video") { [weak self] in
                    guard let self else { return }
                    self.push(SubmissionScreen(self.context))
                })
        }
        let caption = Theme.stack([position, byline, titleLabel, detail, failure], spacing: 3)
        titleLabel.numberOfLines = 2
        detail.numberOfLines = 2
        failure.isHidden = true
        let bottom = Theme.stack([caption, rail], spacing: 10, axis: .horizontal)
        bottom.alignment = .bottom
        progress.minimumTrackTintColor = Theme.lime
        progress.maximumTrackTintColor = Theme.secondary.withAlphaComponent(0.25)
        progress.accessibilityLabel = "Playback position"
        progress.addAction(UIAction { [weak self] _ in self?.requestedSeek = true }, for: .touchDown)
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .valueChanged] {
            progress.addAction(UIAction { [weak self] _ in self?.seek() }, for: event)
        }
        let safe = view.safeAreaLayoutGuide
        for item in [top, bottom, progress] {
            view.addSubview(item)
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlayback))
        video.addGestureRecognizer(tap)
        for direction: UISwipeGestureRecognizer.Direction in [.up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(page(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(inactive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(active), name: UIApplication.didBecomeActiveNotification, object: nil)
        syncClips()
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
        clips = (fixedClips ?? context.catalog.shorts).filter { !context.state.hidden.contains($0.id) }
        feedIndex =
            wanted.flatMap { id in clips.firstIndex { $0.id == id } } ?? min(feedIndex, max(0, clips.count - 1))
        selectedID = nil
        if prior != clip?.id || queue == nil { loadClip() } else { drawRail() }
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
        position.text = "\(feedIndex + 1) of \(clips.count)  ·  \(clip.duration)s"
        let expected = clip.id
        PictureLoader.shared.load(context.asset(clip.cover), into: nil) { [weak self] image in
            guard self?.clip?.id == expected else { return }
            self?.poster.image = image
        }
        guard let url = context.asset(clip.media) else {
            drawRail()
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = muted
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
        guard let clip else { return }
        let avatar = Theme.icon("watch", label: "About \(clip.publisher)") { [weak self] in
            guard let self else { return }
            self.push(ClipCreditsScreen(self.context, clip: clip))
        }
        let liked = context.state.likes.contains(clip.id)
        let saved = context.state.saves.contains(clip.id)
        let like = Theme.icon("like", label: liked ? "Unlike clip" : "Like clip") { [weak self] in
            self?.change(clip, kind: .like, enabled: !liked)
        }
        let comment = Theme.icon("comment", label: "Read and add private notes") { [weak self] in
            guard let self else { return }
            self.push(DiscussionScreen(self.context, clip: clip))
        }
        let save = Theme.icon("save", label: saved ? "Remove saved clip" : "Save clip") { [weak self] in
            self?.change(clip, kind: .save, enabled: !saved)
        }
        for (button, selected) in [(like, liked), (save, saved)] {
            if selected {
                button.accessibilityTraits.insert(.selected)
                button.layer.shadowColor = Theme.lime.cgColor
                button.layer.shadowRadius = 8
                button.layer.shadowOpacity = 1
                button.layer.shadowOffset = .zero
            }
        }
        let shareButton = Theme.icon("share", label: "Share clip") {}
        shareButton.addAction(
            UIAction { [weak self, weak shareButton] _ in
                guard let self, let shareButton else { return }
                self.inactive()
                let sheet = UIActivityViewController(activityItems: [clip.source], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = shareButton
                sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.active() }
                self.present(sheet, animated: true)
            }, for: .touchUpInside)
        let playback = Theme.icon(paused ? "play" : "pause", label: paused ? "Play" : "Pause") { [weak self] in
            self?.togglePlayback()
        }
        let sound = Theme.icon(muted ? "muted" : "sound", label: muted ? "Unmute" : "Mute") { [weak self] in
            guard let self else { return }
            self.muted.toggle()
            self.queue?.isMuted = self.muted
            self.drawRail()
        }
        let more = Theme.icon("more", label: "More clip actions") {}
        more.showsMenuAsPrimaryAction = true
        more.menu = UIMenu(children: [
            UIAction(title: "Clip source and license") { [weak self] _ in
                guard let self else { return }
                self.push(ClipCreditsScreen(self.context, clip: clip))
            },
            UIAction(title: "Hide clip", attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                self.push(
                    HideContentScreen(self.context, target: clip.id) { [weak self] in self?.syncClips()
                    })
            },
        ])
        [avatar, like, comment, save, shareButton, more, sound, playback].forEach(rail.addArrangedSubview)
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
        if !failure.isHidden {
            loadClip()
            return
        }
        paused.toggle()
        if paused { inactive() } else { active() }
        drawRail()
    }

    @objc private func page(_ gesture: UISwipeGestureRecognizer) {
        let next = feedIndex + (gesture.direction == .up ? 1 : -1)
        if clips.indices.contains(next) {
            feedIndex = next
            paused = false
            loadClip()
            return
        }
        if gesture.direction == .down, fixedClips == nil {
            perform {
                try self.context.reload()
                self.syncClips()
            }
        }
    }

    @objc private func inactive() { queue?.pause() }

    @objc private func active() {
        guard !paused, visible, viewIfLoaded?.window != nil, presentedViewController == nil,
            UIApplication.shared.applicationState == .active,
            navigationController?.topViewController === self
        else { return }
        queue?.play()
    }
}

@MainActor final class ClipSearchScreen: ListScreen {
    private let search = Theme.field("Find a player, rally or match")
    private let results = Theme.stack(spacing: 10)

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Search shorts"
        search.addAction(UIAction { [weak self] _ in self?.draw() }, for: .editingChanged)
        render([search, results])
        draw()
    }

    override func refreshContent() async throws {
        try context.reload()
        draw()
    }

    private func draw() {
        let term = search.text?.trimmed ?? ""
        let matches = context.catalog.shorts.filter {
            !context.state.hidden.contains($0.id)
                && (term.isEmpty
                    || "\($0.title) \($0.publisher) \($0.detail)".localizedCaseInsensitiveContains(term))
        }
        for view in results.arrangedSubviews {
            results.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for clip in matches {
            results.addArrangedSubview(
                Theme.button(clip.title) { [weak self] in
                    guard let self else { return }
                    self.push(ShortsScreen(self.context, clips: matches, selected: clip.id))
                })
        }
        if matches.isEmpty { results.addArrangedSubview(Theme.label("No matching clips.")) }
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
                guard let self else { return }
                self.open(self.clip.source)
            },
            Theme.button("View license") { [weak self] in
                guard let self else { return }
                self.open(self.clip.licenseURL)
            },
        ])
    }
}
