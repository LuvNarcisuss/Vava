import AVFoundation
import AVKit
import UIKit

@MainActor final class ProfileScreen: ListScreen {
    private enum Collection: String, CaseIterable {
        case works = "Works"
        case liked = "Liked"
        case saved = "Saved"
        case learning = "Learning"
    }

    private var selection = Collection.works
    private var submissions: [Submission] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Me"
        toolbar.addArrangedSubview(
            Theme.icon("settings", label: "Settings") { [weak self] in
                guard let self else { return }
                self.push(SettingsScreen(self.context))
            })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draw()
        perform { try await self.refreshContent() }
    }

    override func refreshContent() async throws {
        try context.reloadState()
        submissions = try context.library.submissions()
        draw()
    }

    private func draw() {
        let profile = context.state.me
        let picture = Theme.photo("welcome", ratio: 0.37)
        let description = Theme.label(
            profile.bio.isEmpty ? "Add a bio in Settings." : profile.bio, color: Theme.secondary)
        let wallet = Theme.button(
            "Wallet  ·  \(context.wallet.ledger.balance.formatted()) coins", primary: true
        ) { [weak self] in
            guard let self else { return }
            self.push(WalletScreen(self.context))
        }
        let pick = Theme.button(selection.rawValue) {}
        pick.showsMenuAsPrimaryAction = true
        pick.menu = UIMenu(
            children: Collection.allCases.map { item in
                UIAction(title: item.rawValue, state: item == selection ? .on : .off) { [weak self] _ in
                    self?.selection = item
                    self?.draw()
                }
            })
        var views: [UIView] = [
            Theme.card([
                picture, Theme.label(profile.name, size: 29, display: true),
                description,
            ]),
            wallet, pick,
        ]
        switch selection {
        case .works:
            views.append(
                Theme.card([
                    Theme.label("Videos saved on this device appear here.", color: Theme.secondary),
                    Theme.button("Add a video") { [weak self] in
                        guard let self else { return }
                        self.push(SubmissionScreen(self.context))
                    },
                ]))
            if submissions.isEmpty {
                views.append(Theme.label("No videos saved yet.", color: Theme.secondary))
            }
            for submission in submissions {
                views.append(
                    Theme.card([
                        Theme.label(submission.title, size: 22, display: true),
                        Theme.button("Play video") { [weak self] in self?.play(submission) },
                        Theme.button("Remove video") { [weak self] in self?.remove(submission) },
                    ]))
            }
        case .liked:
            let clips = clips(with: context.state.likes)
            views +=
                clips.isEmpty ? [Theme.label("No liked clips yet.", color: Theme.secondary)] : clipRows(clips)
        case .saved:
            let clips = clips(with: context.state.saves)
            views += clipRows(clips)
            for replay in context.catalog.replays
            where context.state.saves.contains(replay.id) && !context.state.hidden.contains(replay.id) {
                views.append(
                    Theme.button(replay.title) { [weak self] in
                        guard let self else { return }
                        self.push(ReplayScreen(self.context, replay: replay))
                    })
            }
            for course in context.catalog.courses where context.state.saves.contains(course.id) {
                views.append(courseRow(course))
            }
            if views.count == 3 { views.append(Theme.label("No saved items yet.", color: Theme.secondary)) }
        case .learning:
            let courses = context.catalog.courses.filter {
                context.wallet.ledger.owned.contains($0.id) || !(context.state.practice[$0.id] ?? []).isEmpty
            }
            views +=
                courses.isEmpty
                ? [Theme.label("Start a lesson in Academy.", color: Theme.secondary)] : courses.map(courseRow)
        }
        render(views)
    }

    private func clips(with ids: [String]) -> [Clip] {
        context.catalog.shorts.filter { ids.contains($0.id) && !context.state.hidden.contains($0.id) }
    }

    private func clipRows(_ clips: [Clip]) -> [UIView] {
        clips.map { clip in
            Theme.button(clip.title) { [weak self] in
                guard let self else { return }
                self.push(ShortsScreen(self.context, clips: clips, selected: clip.id))
            }
        }
    }

    private func courseRow(_ course: Course) -> UIView {
        let count = context.state.practice[course.id]?.count ?? 0
        return Theme.button("\(course.title)  ·  \(count) drills complete") { [weak self] in
            guard let self else { return }
            self.push(CourseScreen(self.context, course: course))
        }
    }

    private func play(_ submission: Submission) {
        perform {
            let url = try self.context.library.submissionURL(submission)
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(url: url)
            self.present(controller, animated: true) { controller.player?.play() }
        }
    }

    private func remove(_ submission: Submission) {
        confirm(
            "Remove this video?", message: "The original in Photos stays on your device.",
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

@MainActor final class SettingsScreen: ListScreen {

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Settings"
        let agreementButtons = Agreement.allCases.map { agreement in
            Theme.button(agreement.rawValue) { [weak self] in self?.push(AgreementScreen(agreement)) }
        }
        let edit = Theme.button("Edit profile") { [weak self] in
            guard let self else { return }
            self.push(EditProfileScreen(self.context))
        }
        let credits = Theme.button("Media credits") { [weak self] in
            guard let self else { return }
            self.push(CreditsScreen(self.context))
        }
        let delete = Theme.button("Delete local profile") { [weak self] in self?.deleteProfile() }
        render([edit, credits] + agreementButtons + [delete])
    }

    private func deleteProfile() {
        confirm(
            "Delete local profile?",
            message:
                "This removes the profile, saved activity, imported copies, coins and course access from this device.",
            action: "Delete profile", destructive: true
        ) { [weak self] in
            guard let self else { return }
            self.perform { try self.context.deleteLocalProfile() }
        }
    }

}

@MainActor final class EditProfileScreen: ListScreen {
    private lazy var name = Theme.field("Display name", value: context.state.me.name)
    private lazy var biography = Theme.field("Bio", value: context.state.me.bio)
    private var saving = false

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Edit profile"
        render([name, biography, Theme.button("Save profile", primary: true) { [weak self] in self?.save() }])
    }

    private func save() {
        guard !saving else { return }
        let name = self.name.text?.trimmed ?? ""
        let bio = biography.text?.trimmed ?? ""
        guard (1...40).contains(name.count), bio.count <= 180 else {
            show("Check your profile", message: "Use 1–40 characters for your name and up to 180 for your bio.")
            return
        }
        saving = true
        perform {
            defer { self.saving = false }
            try self.context.library.editProfile(name: name, bio: bio)
            try self.context.reloadState()
            self.navigationController?.popViewController(animated: true)
        }
    }
}

@MainActor final class CreditsScreen: ListScreen {
    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Media credits"
        let clips = context.catalog.shorts.map { clip in
            Theme.button("\(clip.title)  ·  \(clip.publisher)") { [weak self] in
                guard let self else { return }
                self.push(ClipCreditsScreen(self.context, clip: clip))
            }
        }
        let replays = context.catalog.replays.map { replay in
            Theme.button("\(replay.title)  ·  \(replay.publisher)") { [weak self] in self?.open(replay.source) }
        }
        render(clips + replays)
    }
}
