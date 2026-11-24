import UIKit

// Included only in the isolated safety harness, never in the application target.
@main @MainActor final class SafetyTestHost: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var context: AppContext?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("com.vava.walletacceptance.") == true)
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--safety-account")!
        let account = UUID(uuidString: arguments[index + 1])!
        do {
            let library = try LocalLibrary(account: account)
            let profile = try library.open(revision: "2026-11-13.2", accepted: true)
            let catalog: Catalog = Bundle.main.decode("catalog")!
            let wallet = try Wallet(account: profile.id)
            let context = try AppContext(library: library, wallet: wallet, catalog: catalog)
            self.context = context
            if arguments.contains("--seed-safety") {
                let clip = catalog.shorts[0]
                try library.change(clip.id, kind: .save, enabled: true)
                try library.change(catalog.courses[0].id, kind: .save, enabled: true)
                try library.markPractice(course: catalog.courses[0].id, step: 0, completed: true)
                try library.addChatEntry(
                    ChatEntry(id: UUID(), text: "Saved conversation", date: Date(), kind: .notice),
                    for: ChatPerson(clip.author))
                try context.reloadState()
            }
            if arguments.contains("--fail-safety-writes") {
                let files = FileManager.default
                let support = try files.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: false)
                let index = support.appendingPathComponent("AccountLibraries")
                    .appendingPathComponent(account.uuidString).appendingPathComponent("library.json")
                try files.moveItem(at: index, to: index.appendingPathExtension("backup"))
                try files.createDirectory(at: index, withIntermediateDirectories: false)
                try Data("Blocked write".utf8).write(to: index.appendingPathComponent("obstacle"))
            }
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = Dock(context)
            window.makeKeyAndVisible()
            self.window = window
            return true
        } catch {
            fatalError("Safety fixture could not start: \(error)")
        }
    }
}
