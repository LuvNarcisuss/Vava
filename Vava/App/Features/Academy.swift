import UIKit

@MainActor final class AcademyScreen: ListScreen {
    override func contentVisibilityDidChange() { draw() }

    private var category = "All topics"
    private var pricing = "All prices"
    private let search = Theme.field("Search lessons")
    private var showSearch = false

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Academy"
        toolbar.addArrangedSubview(
            Theme.icon("search", label: "Search lessons") { [weak self] in self?.toggleSearch() })
        let filter = Theme.icon("filter", label: "Filter lessons") {}
        filter.showsMenuAsPrimaryAction = true
        toolbar.addArrangedSubview(filter)
        search.addAction(UIAction { [weak self] _ in self?.draw() }, for: .editingChanged)
        draw()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
    }

    override func refreshContent() async throws {
        try context.reload()
        draw()
    }

    private func toggleSearch() {
        showSearch.toggle()
        if !showSearch {
            search.resignFirstResponder()
            search.text = ""
        }
        draw()
        if showSearch { search.becomeFirstResponder() }
    }

    private func draw() {
        let topics = ["All topics", "Saved"] + Set(context.catalog.courses.map(\.category)).sorted()
        let prices = ["All prices", "Free", "Coin unlock"]
        func menu(_ values: [String], selection: String, select: @escaping (String) -> Void) -> UIMenu {
            UIMenu(
                options: .displayInline,
                children: values.map { value in
                    UIAction(title: value, state: value == selection ? .on : .off) { _ in select(value) }
                })
        }
        (toolbar.arrangedSubviews.last as? UIButton)?.menu = UIMenu(children: [
            menu(topics, selection: category) { [weak self] in
                self?.category = $0
                self?.draw()
            },
            menu(prices, selection: pricing) { [weak self] in
                self?.pricing = $0
                self?.draw()
            },
        ])
        let term = search.text?.trimmed ?? ""
        let items = context.catalog.courses.filter {
            let topicMatches =
                category == "All topics" || $0.category == category
                || (category == "Saved" && context.state.saves.contains($0.id))
            let priceMatches =
                pricing == "All prices" || ($0.price == 0 ? pricing == "Free" : pricing == "Coin unlock")
            let textMatches =
                term.isEmpty
                || "\($0.title) \($0.category) \($0.detail) \($0.author.name)".localizedCaseInsensitiveContains(
                    term)
            return context.state.canShow($0) && topicMatches && priceMatches && textMatches
        }
        let rows = items.rotated(by: refreshOrder).map { course -> UIView in
            let image = Theme.photo(ratio: 0.46)
            PictureLoader.shared.load(context.asset(course.cover), into: image)
            let unlocked = context.wallet.ledger.owned.contains(course.id)
            let price = course.price == 0 ? "Free" : unlocked ? "Unlocked" : "\(course.price) coins"
            let header = Theme.label(
                "\(course.category.uppercased())  /  \(course.minutes) MIN", size: 13, color: Theme.lime)
            let title = Theme.label(course.title, size: 25, display: true)
            let priceLabel = Theme.label(price, display: true, color: Theme.lime)
            let details = Theme.stack(
                [image, header, title, Theme.label(course.detail, color: Theme.secondary), priceLabel],
                spacing: 8)
            details.isUserInteractionEnabled = false
            details.accessibilityElementsHidden = true

            let open = UIButton(type: .custom)
            open.accessibilityLabel = "\(course.title), \(price)"
            open.accessibilityValue = "\(course.category), \(course.minutes) min. \(course.detail)"
            open.addAction(
                UIAction { [weak self] _ in
                    guard let self else { return }
                    self.push(CourseScreen(self.context, course: course))
                }, for: .touchUpInside)
            details.pin(to: open)
            let author = courseAuthorButton(course)
            let more = courseActions(course) { [weak self] in self?.draw() }
            let attribution = Theme.stack([author, more], spacing: 8, axis: .horizontal)
            attribution.alignment = .center
            return Theme.card([open, attribution])
        }
        let views: [UIView] =
            [Theme.label("Build a better point.", size: 20, color: Theme.secondary)]
            + (rows.isEmpty ? [Theme.card([Theme.label("No matching lessons.")])] : rows)
        if showSearch, search.superview === body {
            for view in body.arrangedSubviews where view !== search {
                body.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            views.forEach(body.addArrangedSubview)
        } else {
            render((showSearch ? [search as UIView] : []) + views)
        }
    }
}

@MainActor final class CourseScreen: ListScreen {
    override func contentVisibilityDidChange() { draw() }

    private let course: Course
    private var writing = false
    private var unlocked: Bool { course.price == 0 || context.wallet.ledger.owned.contains(course.id) }
    override var showsHeadingInToolbar: Bool { false }

    init(_ context: AppContext, course: Course) {
        self.course = course
        super.init(context)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = course.title
        heading.font = Theme.font(24, display: true)
        heading.numberOfLines = 1
        heading.adjustsFontSizeToFitWidth = true
        heading.minimumScaleFactor = 0.75
        heading.lineBreakMode = .byTruncatingTail
        toolbar.addArrangedSubview(
            courseActions(course) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
        draw()
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
        guard context.state.canShow(course) else {
            render([heading, Theme.label("This lesson is hidden from your lists.", color: Theme.secondary)])
            toolbar.isHidden = true
            return
        }
        toolbar.isHidden = false
        let image = Theme.photo()
        PictureLoader.shared.load(context.asset(course.cover), into: image)
        let saved = context.state.saves.contains(course.id)
        let save = Theme.button(saved ? "Remove from saved" : "Save lesson") { [weak self] in
            guard let self else { return }
            self.perform {
                try self.context.change(self.course.id, kind: .save, enabled: !saved)
                self.draw()
            }
        }
        var views: [UIView] = [
            heading, image, courseAuthorButton(course),
            Theme.label("\(course.level)  /  \(course.minutes) min", color: Theme.lime),
            Theme.label(course.detail, size: 20), save,
        ]
        if unlocked {
            let completed = Set(context.state.practice[course.id] ?? [])
            if let steps = course.steps {
                views.append(
                    Theme.label("Practice  \(completed.count)/\(steps.count)", size: 23, display: true))
                for (index, step) in steps.enumerated() {
                    let title = completed.contains(index) ? "Completed" : "Mark complete"
                    let button = Theme.button(title, primary: completed.contains(index)) { [weak self] in
                        guard let self, !self.writing else { return }
                        self.writing = true
                        self.perform {
                            defer { self.writing = false }
                            try self.context.library.markPractice(
                                course: self.course.id, step: index, completed: !completed.contains(index))
                            try self.context.reloadState()
                            self.draw()
                        }
                    }
                    views.append(
                        Theme.card([
                            Theme.label("Drill \(index + 1)", size: 16, display: true, color: Theme.lime),
                            Theme.label(step), button,
                        ]))
                }
            } else {
                views.append(Theme.label("Practice steps are unavailable."))
            }
        } else {
            views.append(
                Theme.card([
                    Theme.label("Unlock the practice plan", size: 24, display: true),
                    Theme.label("Unlock once to access the practice plan."),
                    Theme.button("Unlock for \(course.price) coins", primary: true) { [weak self] in
                        self?.requestUnlock()
                    },
                ]))
        }
        views.append(
            Theme.card([
                Theme.label("Coaching reference", size: 20, display: true),
                Theme.button(course.referenceName) { [weak self] in
                    guard let self else { return }
                    self.open(self.course.reference)
                },
            ]))
        render(views)
    }

    private func requestUnlock() {
        if context.wallet.ledger.balance < course.price {
            confirm(
                "More coins needed", message: "Your balance is \(context.wallet.ledger.balance) coins.",
                action: "Open wallet"
            ) { [weak self] in
                guard let self else { return }
                self.push(WalletScreen(self.context))
            }
        } else {
            confirm(
                "Unlock this course?", message: "Spend \(course.price) coins on \(course.title).",
                action: "Unlock"
            ) { [weak self] in
                guard let self else { return }
                self.perform {
                    try self.context.wallet.unlock(self.course)
                    self.draw()
                }
            }
        }
    }
}

extension Screen {
    fileprivate func courseAuthorButton(_ course: Course) -> UIButton {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = course.author.name
        button.accessibilityHint = "Opens the coaching source profile"
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let avatar = Theme.avatar(40, source: context.portrait(for: course.author))
        let name = Theme.label(course.author.name, size: 16, display: true)
        let credit = Theme.label("Coaching reference", size: 13, color: Theme.secondary)
        let row = Theme.stack(
            [avatar, Theme.stack([name, credit], spacing: 1)], spacing: 8, axis: .horizontal)
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.accessibilityElementsHidden = true
        row.pin(to: button, top: 2, bottom: 2)
        button.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.push(PublisherProfileScreen(self.context, publisher: course.author, openTutorials: true))
            }, for: .touchUpInside)
        return button
    }

    fileprivate func courseActions(_ course: Course, onChange: @escaping () -> Void) -> UIButton {
        let more = Theme.icon("more", label: "More lesson actions") {}
        more.showsMenuAsPrimaryAction = true
        more.menu = UIMenu(children: [
            UIAction(title: "Report lesson", attributes: .destructive) { [weak self] _ in
                self?.reportContent(course.id, title: "Report lesson", onChange: onChange)
            },
            UIAction(title: "Block publisher", attributes: .destructive) { [weak self] _ in
                self?.blockPublisher(course.author)
            },
        ])
        return more
    }
}
