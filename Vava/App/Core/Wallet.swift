import Foundation
import StoreKit

struct CoinPack: Decodable, Identifiable {
    var id: Int { coins }
    let coins: Int
    let productID: String

    static let all: [Self] = Bundle.main.decode("coin-products") ?? []
}

struct WalletEntry: Codable, Identifiable {
    let id: String
    let title: String
    let amount: Int
    let date: Date
}

struct WalletLedger: Codable {
    var balance = 0
    var entries: [WalletEntry] = []
    var owned: Set<String> = []

    mutating func credit(id: String, amount: Int) throws {
        guard !entries.contains(where: { $0.id == id }) else { return }
        let (total, overflow) = balance.addingReportingOverflow(amount)
        guard amount > 0, !overflow else { throw AppFailure("The coin amount could not be saved.") }
        balance = total
        entries.insert(WalletEntry(id: id, title: "Coin pack", amount: amount, date: Date()), at: 0)
    }

    mutating func unlock(_ course: Course) throws {
        guard course.price > 0, !owned.contains(course.id) else { return }
        guard balance >= course.price else { throw AppFailure("You need more coins to unlock this course.") }
        balance -= course.price
        owned.insert(course.id)
        entries.insert(
            WalletEntry(
                id: "course:\(course.id)", title: course.title,
                amount: -course.price, date: Date()), at: 0)
    }
}

@MainActor final class Wallet {
    private let account: UUID
    private let file: URL
    private var observer: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var products: [String: Product] = [:]
    private var catalogRequest: Task<[Product], Error>?
    private(set) var ledger: WalletLedger
    private(set) var busy = false
    private(set) var active = true

    init(account: UUID) throws {
        self.account = account
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        .appendingPathComponent("Wallets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent(account.uuidString + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            ledger = try JSONDecoder().decode(WalletLedger.self, from: Data(contentsOf: file))
        } else {
            ledger = WalletLedger()
        }
        observer = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, self.active, !Task.isCancelled else { return }
                try? await self.deliver(result)
            }
        }
        recovery = Task { [weak self] in
            for await result in Transaction.unfinished {
                guard let self, self.active, !Task.isCancelled else { return }
                try? await self.deliver(result)
            }
        }
    }

    func stop() {
        active = false
        observer?.cancel()
        recovery?.cancel()
        catalogRequest?.cancel()
    }

    func purge() throws {
        stop()
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    func refresh() async throws {
        let ids = Set(CoinPack.all.map(\.productID).filter { !$0.isEmpty })
        guard !ids.isEmpty, active else {
            products = [:]
            return
        }
        if let catalogRequest {
            _ = try await catalogRequest.value
            return
        }
        let request = Task { try await Product.products(for: ids) }
        catalogRequest = request
        defer { catalogRequest = nil }
        do {
            let loaded = try await request.value
            guard active else { throw CancellationError() }
            products = Dictionary(
                uniqueKeysWithValues: loaded.filter { $0.type == .consumable }.map { ($0.id, $0) })
        } catch {
            products = [:]
            throw error
        }
    }

    func price(for pack: CoinPack) -> String? { products[pack.productID]?.displayPrice }
    var paymentsAllowed: Bool { AppStore.canMakePayments }

    func buy(_ pack: CoinPack, price: String) async throws -> String {
        guard active, !busy, paymentsAllowed, let product = products[pack.productID],
            product.displayPrice == price
        else { throw AppFailure("This coin pack is unavailable.") }
        busy = true
        defer { busy = false }
        switch try await product.purchase(options: [.appAccountToken(account)]) {
        case .success(let result):
            try await deliver(result)
            return "Coins added to your wallet."
        case .pending:
            return "Waiting for purchase approval."
        case .userCancelled:
            return "Purchase canceled."
        @unknown default:
            throw AppFailure("The purchase status is unavailable.")
        }
    }

    func unlock(_ course: Course) throws {
        guard active else { throw AppFailure("Open your wallet to continue.") }
        var next = ledger
        try next.unlock(course)
        try persist(next)
    }

    private func deliver(_ result: VerificationResult<Transaction>) async throws {
        guard active, case .verified(let transaction) = result,
            transaction.environment == .sandbox || transaction.environment == .production,
            transaction.appAccountToken == account, transaction.revocationDate == nil,
            transaction.productType == .consumable,
            let pack = CoinPack.all.first(where: {
                !$0.productID.isEmpty && $0.productID == transaction.productID
            })
        else { throw AppFailure("This transaction could not be credited to your wallet.") }
        let (amount, overflow) = pack.coins.multipliedReportingOverflow(by: transaction.purchasedQuantity)
        guard !overflow else { throw AppFailure("The coin amount could not be saved.") }
        var next = ledger
        try next.credit(id: "apple:\(transaction.id)", amount: amount)
        try persist(next)
        await transaction.finish()
    }

    private func persist(_ next: WalletLedger) throws {
        try JSONEncoder().encode(next).write(
            to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        ledger = next
        NotificationCenter.default.post(name: .walletChanged, object: self)
    }
}

extension Notification.Name {
    static let walletChanged = Notification.Name("Vava.WalletChanged")
}
