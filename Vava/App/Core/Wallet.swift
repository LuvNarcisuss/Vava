import Foundation
import OSLog
import StoreKit

struct CoinPack: Decodable, Identifiable {
    var id: String { productID }
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
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Vava", category: "InAppPurchase")
    private let account: UUID
    private let appleFile: URL
    private let localFile: URL
    private let localStoreKit: Bool
    private var file: URL { localStoreKit ? localFile : appleFile }
    private var observer: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var products: [String: Product] = [:]
    private var catalogRequest: Task<Void, Error>?
    private var failedTransactions: Set<UInt64> = []
    private(set) var ledger: WalletLedger
    private(set) var busy = false
    private(set) var active = true
    private(set) var retryingPurchases = false
    var hasPurchaseIssue: Bool { !failedTransactions.isEmpty }

    init(account: UUID) throws {
        self.account = account
        #if DEBUG
            let storeKitMode = ProcessInfo.processInfo.environment["VAVA_LOCAL_STOREKIT"]
            #if targetEnvironment(simulator)
                localStoreKit = storeKitMode != "0"
            #else
                localStoreKit = storeKitMode == "1"
            #endif
        #else
            localStoreKit = false
        #endif
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let (appleFile, localFile) = Self.ledgerFiles(for: account, in: support)
        self.appleFile = appleFile
        self.localFile = localFile
        let ledgerFile = localStoreKit ? localFile : appleFile
        try FileManager.default.createDirectory(
            at: ledgerFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: ledgerFile.path) {
            ledger = try JSONDecoder().decode(WalletLedger.self, from: Data(contentsOf: ledgerFile))
        } else {
            ledger = WalletLedger()
        }
        observer = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, self.active, !Task.isCancelled else { return }
                await self.receive(result)
            }
        }
        recovery = Task { [weak self] in
            await self?.retryPendingPurchases()
        }
    }

    func retryPendingPurchases() async {
        guard active, !retryingPurchases else { return }
        retryingPurchases = true
        notifyChange()
        defer {
            retryingPurchases = false
            notifyChange()
        }
        for await result in Transaction.unfinished {
            guard active, !Task.isCancelled else { return }
            await receive(result)
        }
    }

    private func receive(_ result: VerificationResult<Transaction>) async {
        // Unverified fields only scope feedback; credit still requires full verification.
        let transaction = result.unsafePayloadValue
        guard active, transaction.appAccountToken == account,
            accepts(transaction.environment), transaction.productType == .consumable
        else { return }
        if transaction.revocationDate != nil {
            if failedTransactions.remove(transaction.id) != nil { notifyChange() }
            return
        }
        do {
            try await deliver(result)
        } catch {
            // Delivery retains the failure for the wallet's explicit retry flow.
        }
    }

    func stop() {
        active = false
        observer?.cancel()
        recovery?.cancel()
        catalogRequest?.cancel()
    }

    private static func ledgerFiles(for account: UUID, in support: URL) -> (URL, URL) {
        let filename = account.uuidString + ".json"
        return (
            support.appendingPathComponent("Wallets", isDirectory: true).appendingPathComponent(filename),
            support.appendingPathComponent("LocalStoreKitWallets", isDirectory: true).appendingPathComponent(
                filename)
        )
    }

    static func removeLedgers(for account: UUID, in support: URL) throws {
        let (appleFile, localFile) = ledgerFiles(for: account, in: support)
        for ledgerFile in [appleFile, localFile] {
            do { try FileManager.default.removeItem(at: ledgerFile) } catch let error as CocoaError
                where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
            { continue }
        }
    }

    func refresh() async throws {
        let ids = Set(CoinPack.all.map(\.productID).filter { !$0.isEmpty })
        guard !ids.isEmpty, active else {
            products = [:]
            return
        }
        if let catalogRequest { return try await catalogRequest.value }
        let request = Task<Void, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            defer { self.catalogRequest = nil }
            do {
                let mode = self.localStoreKit ? "Xcode" : "App Store"
                let canPay = self.paymentsAllowed
                Self.log.info(
                    "Loading \(ids.count) products in \(mode, privacy: .public). Payments allowed: \(canPay).")
                let loaded = try await Product.products(for: ids)
                guard self.active, !Task.isCancelled else { throw CancellationError() }
                self.products = Dictionary(
                    uniqueKeysWithValues: loaded.filter { ids.contains($0.id) && $0.type == .consumable }
                        .map { ($0.id, $0) })
                let missing = ids.subtracting(self.products.keys).sorted().joined(separator: ", ")
                if !missing.isEmpty {
                    Self.log.notice(
                        "StoreKit did not return eligible consumables for: \(missing, privacy: .public).")
                }
            } catch {
                self.products = [:]
                let failure = error as NSError
                Self.log.error("Product load ended with \(failure.domain, privacy: .public) \(failure.code).")
                throw error
            }
        }
        catalogRequest = request
        try await request.value
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
        let id = result.unsafePayloadValue.id
        do {
            try await creditVerifiedTransaction(result)
            if failedTransactions.remove(id) != nil { notifyChange() }
        } catch {
            if active {
                failedTransactions.insert(id)
                notifyChange()
                let failure = error as NSError
                Self.log.error(
                    "Purchase delivery failed with \(failure.domain, privacy: .public) \(failure.code). Retry is available."
                )
            }
            throw error
        }
    }

    private func creditVerifiedTransaction(_ result: VerificationResult<Transaction>) async throws {
        guard active, case .verified(let transaction) = result,
            accepts(transaction.environment),
            transaction.appAccountToken == account, transaction.revocationDate == nil,
            transaction.productType == .consumable,
            let pack = CoinPack.all.first(where: {
                !$0.productID.isEmpty && $0.productID == transaction.productID
            })
        else { throw AppFailure("This transaction could not be credited to your wallet.") }
        let id = "apple:\(transaction.id)"
        if !ledger.entries.contains(where: { $0.id == id }) {
            let (amount, overflow) = pack.coins.multipliedReportingOverflow(by: transaction.purchasedQuantity)
            guard !overflow else { throw AppFailure("The coin amount could not be saved.") }
            var next = ledger
            try next.credit(id: id, amount: amount)
            try persist(next)
        }
        await transaction.finish()
    }

    private func accepts(_ environment: AppStore.Environment) -> Bool {
        localStoreKit ? environment == .xcode : environment == .sandbox || environment == .production
    }

    private func persist(_ next: WalletLedger) throws {
        try JSONEncoder().encode(next).write(
            to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        ledger = next
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .walletChanged, object: self)
    }
}

extension Notification.Name {
    static let walletChanged = Notification.Name("Vava.WalletChanged")
}
