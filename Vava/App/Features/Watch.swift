import UIKit

@MainActor final class WatchScreen: ListScreen {
    override func contentVisibilityDidChange() { draw() }

    private let search = Theme.field("Search matches")
    private var searching = false
    private var event = "All events"

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Watch"
        toolbar.addArrangedSubview(
            Theme.icon("search", label: "Search replays") { [weak self] in
                guard let self else { return }
                self.searching.toggle()
                if !self.searching {
                    self.search.resignFirstResponder()
                    self.search.text = ""
                }
                self.draw()
                if self.searching { self.search.becomeFirstResponder() }
            })
        let filter = Theme.icon("filter", label: "Filter by event") {}
        filter.showsMenuAsPrimaryAction = true
        toolbar.addArrangedSubview(filter)
        search.addAction(UIAction { [weak self] _ in self?.draw() }, for: .editingChanged)
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
        let events = ["All events", "Saved"] + Set(context.catalog.replays.map(\.event)).sorted()
        (toolbar.arrangedSubviews.last as? UIButton)?.menu = UIMenu(
            children: events.map { choice in
                UIAction(title: choice, state: choice == event ? .on : .off) { [weak self] _ in
                    self?.event = choice
                    self?.draw()
                }
            })
        let query = search.text?.trimmed ?? ""
        let replays = context.catalog.replays.filter {
            !context.state.hidden.contains($0.id)
                && (event == "All events" || event == $0.event
                    || (event == "Saved" && context.state.saves.contains($0.id)))
                && (query.isEmpty || "\($0.title) \($0.event)".localizedCaseInsensitiveContains(query))
        }
        var views: [UIView] = [Theme.label("Match replays", size: 20, color: Theme.secondary)]
        for replay in replays.rotated(by: refreshOrder) {
            let cover = Theme.photo()
            PictureLoader.shared.load(context.asset(replay.cover), into: cover)
            let card = Theme.card([
                cover, Theme.label(replay.event.uppercased(), size: 13, color: Theme.lime),
                Theme.label(replay.title, size: 24, display: true),
                Theme.label("View replay", display: true, color: Theme.lime),
            ])
            card.isUserInteractionEnabled = false
            card.accessibilityElementsHidden = true
            let open = UIButton(type: .custom)
            open.accessibilityLabel = replay.title
            open.accessibilityHint = "Opens the replay"
            open.accessibilityValue = replay.event
            open.addAction(
                UIAction { [weak self] _ in
                    guard let self else { return }
                    self.push(ReplayScreen(self.context, replay: replay))
                }, for: .touchUpInside)
            card.pin(to: open)
            views.append(open)
        }
        if replays.isEmpty { views.append(Theme.card([Theme.label("No replays match these filters.")])) }
        if searching, search.superview === body {
            for view in body.arrangedSubviews where view !== search {
                body.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            views.forEach(body.addArrangedSubview)
        } else {
            render((searching ? [search as UIView] : []) + views)
        }
    }
}

@MainActor final class ReplayScreen: ListScreen {
    private let replay: Replay

    init(_ context: AppContext, replay: Replay) {
        self.replay = replay
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Replay"
        draw()
    }

    override func refreshContent() async throws {
        try context.reload()
        draw()
    }

    private func draw() {
        let cover = Theme.photo()
        PictureLoader.shared.load(context.asset(replay.cover), into: cover)
        let saved = context.state.saves.contains(replay.id)
        let shareButton = Theme.button("Share replay") {}
        shareButton.addAction(
            UIAction { [weak self, weak shareButton] _ in
                guard let self, let shareButton else { return }
                self.share([self.replay.source], from: shareButton)
            }, for: .touchUpInside)
        render([
            cover, Theme.label(replay.event.uppercased(), size: 14, color: Theme.lime),
            Theme.label(replay.title, size: 30, display: true),
            Theme.label("Official replay · \(replay.publisher)", color: Theme.secondary),
            Theme.button("Watch on the publisher's site", primary: true) { [weak self] in
                guard let self else { return }
                self.open(self.replay.source)
            },
            Theme.button(saved ? "Remove from saved" : "Save replay") { [weak self] in
                guard let self else { return }
                self.perform {
                    try self.context.change(self.replay.id, kind: .save, enabled: !saved)
                    self.draw()
                }
            },
            shareButton,
            Theme.button("Hide replay") { [weak self] in
                guard let self else { return }
                self.push(
                    HideContentScreen(self.context, target: self.replay.id, kind: .replay) { [weak self] in
                        self?.navigationController?.popToRootViewController(animated: true)
                    })
            },
        ])
    }
}
