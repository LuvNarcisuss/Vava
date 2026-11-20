import Foundation
import OSLog
import StoreKit
import TPInAppReceipt

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

enum WalletCatalogStatus: String {
    case idle, loading, ready, partial, unavailable, failed
}

// Retains StoreKit 1 delegates until exactly one completion, including cancellation and timeout.
@MainActor private final class StoreRequest: NSObject, SKProductsRequestDelegate {
    private var request: SKRequest?
    private var continuation: CheckedContinuation<[SKProduct], Error>?
    private var timeout: Task<Void, Never>?

    func perform(_ request: SKRequest) async throws -> [SKProduct] {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.request = request
                request.delegate = self
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                    self?.finish(.failure(AppFailure("Prices could not be loaded. Pull down to try again.")))
                }
                request.start()
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor in
            guard self.request === request else { return }
            self.finish(.success(response.products))
        }
    }
    nonisolated func requestDidFinish(_ request: SKRequest) {
        Task { @MainActor in
            guard self.request === request, !(request is SKProductsRequest) else { return }
            self.finish(.success([]))
        }
    }
    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.request === request else { return }
            self.finish(.failure(error))
        }
    }
    private func finish(_ result: Result<[SKProduct], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        request?.delegate = nil
        request?.cancel(); request = nil
        continuation.resume(with: result)
    }
}

@MainActor final class Wallet: NSObject, SKPaymentTransactionObserver {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Vava", category: "InAppPurchase")
    private let account: UUID
    private let appleFile: URL
    private let localFile: URL
    private let localStoreKit: Bool
    private var file: URL { localStoreKit ? localFile : appleFile }
    private var products: [String: SKProduct] = [:]
    private var catalogRequest: Task<Void, Error>?
    private var failedTransactions: Set<String> = []
    private var removedTransactions: Set<String> = []
    private var checkout: (productID: String, continuation: CheckedContinuation<String, Error>)?
    private(set) var ledger: WalletLedger
    private(set) var busy = false
    private(set) var active = true
    private(set) var retryingPurchases = false
    private(set) var catalogStatus: WalletCatalogStatus = .idle
    var hasPurchaseIssue: Bool { !failedTransactions.isEmpty }
    var catalogMessage: String {
        switch catalogStatus {
        case .idle, .loading: return "Loading prices…"
        case .ready: return "Pull down to reload prices."
        case .partial: return "Some coin packs are unavailable. Pull down to reload prices."
        case .unavailable: return "Coin packs are currently unavailable. Pull down to try again."
        case .failed: return "Prices could not be loaded. Pull down to try again."
        }
    }

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
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        let (appleFile, localFile) = Self.ledgerFiles(for: account, in: support)
        self.appleFile = appleFile; self.localFile = localFile
        let ledgerFile = localStoreKit ? localFile : appleFile
        try FileManager.default.createDirectory(at: ledgerFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        ledger = FileManager.default.fileExists(atPath: ledgerFile.path)
            ? try JSONDecoder().decode(WalletLedger.self, from: Data(contentsOf: ledgerFile)) : WalletLedger()
        super.init()
        SKPaymentQueue.default().add(self)
        Task { [weak self] in await self?.retryPendingPurchases() }
    }

    func stop() {
        active = false
        SKPaymentQueue.default().remove(self)
        catalogRequest?.cancel()
        completeCheckout(.failure(CancellationError()))
    }

    private static func ledgerFiles(for account: UUID, in support: URL) -> (URL, URL) {
        let filename = account.uuidString + ".json"
        return (support.appendingPathComponent("Wallets", isDirectory: true).appendingPathComponent(filename),
                support.appendingPathComponent("LocalStoreKitWallets", isDirectory: true).appendingPathComponent(filename))
    }
    static func removeLedgers(for account: UUID, in support: URL) throws {
        let (appleFile, localFile) = ledgerFiles(for: account, in: support)
        for ledgerFile in [appleFile, localFile] {
            do { try FileManager.default.removeItem(at: ledgerFile) } catch let error as CocoaError
                where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { continue }
        }
    }

    func refresh() async throws {
        guard active else { throw CancellationError() }
        if let catalogRequest { return try await catalogRequest.value }
        let ids = Set(CoinPack.all.map(\.productID).filter { !$0.isEmpty })
        catalogStatus = .loading
        notifyChange()
        let request = Task<Void, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            defer { self.catalogRequest = nil; self.notifyChange() }
            do {
                let mode = self.localStoreKit ? "local ledger" : "Apple ledger"
                Self.log.info("StoreKit 1 loading \(ids.count) products; \(mode, privacy: .public).")
                let loader = StoreRequest()
                let loaded = try await loader.perform(SKProductsRequest(productIdentifiers: ids))
                guard self.active, !Task.isCancelled else { throw CancellationError() }
                self.products = Dictionary(uniqueKeysWithValues: loaded.filter { ids.contains($0.productIdentifier) }
                    .map { ($0.productIdentifier, $0) })
                let missing = ids.subtracting(self.products.keys).sorted().joined(separator: ", ")
                Self.log.info("StoreKit 1 returned \(self.products.count) products. Missing: \(missing, privacy: .public)")
                guard !self.products.isEmpty else {
                    self.catalogStatus = .unavailable
                    throw AppFailure(self.catalogMessage)
                }
                self.catalogStatus = missing.isEmpty ? .ready : .partial
            } catch {
                self.products = [:]
                if self.catalogStatus != .unavailable { self.catalogStatus = .failed }
                let failure = error as NSError
                Self.log.error("Product load failed: \(failure.domain, privacy: .public) \(failure.code)")
                if error is CancellationError { throw error }
                throw AppFailure(self.catalogMessage)
            }
        }
        catalogRequest = request
        try await request.value
    }
    func price(for pack: CoinPack) -> String? {
        guard let product = products[pack.productID] else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency; formatter.locale = product.priceLocale
        return formatter.string(from: product.price)
    }
    var paymentsAllowed: Bool { SKPaymentQueue.canMakePayments() }

    func buy(_ pack: CoinPack, price: String) async throws -> String {
        guard active, !busy, paymentsAllowed, let product = products[pack.productID],
              self.price(for: pack) == price else { throw AppFailure("This coin pack is unavailable.") }
        guard !hasPurchaseIssue, !SKPaymentQueue.default().transactions.contains(where: { transaction in
            transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)) == account &&
                (transaction.transactionState == .purchasing || transaction.transactionState == .deferred ||
                 transaction.transactionState == .purchased)
        }) else { throw AppFailure("Please finish or retry your pending purchase before buying again.") }
        busy = true; notifyChange()
        return try await withCheckedThrowingContinuation { continuation in
            checkout = (pack.productID, continuation)
            let payment = SKMutablePayment(product: product)
            payment.applicationUsername = account.uuidString
            payment.quantity = 1
            SKPaymentQueue.default().add(payment)
        }
    }
    private func completeCheckout(_ result: Result<String, Error>, productID: String? = nil) {
        guard let checkout, productID == nil || checkout.productID == productID else { return }
        self.checkout = nil; busy = false
        notifyChange()
        checkout.continuation.resume(with: result)
    }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            for transaction in transactions { await self.receive(transaction) }
        }
    }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            self.removedTransactions.formUnion(transactions.compactMap(\.transactionIdentifier))
        }
    }
    func retryPendingPurchases() async {
        guard active, !retryingPurchases else { return }
        retryingPurchases = true; notifyChange()
        defer { retryingPurchases = false; notifyChange() }
        for transaction in SKPaymentQueue.default().transactions { await receive(transaction) }
    }
    func receive(_ transaction: SKPaymentTransaction) async {
        guard active, transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)) == account else { return }
        let productID = transaction.payment.productIdentifier
        switch transaction.transactionState {
        case .purchased:
            do {
                if try await deliver(transaction) {
                    // finishTransaction is asynchronous. Wait for the queue acknowledgement before allowing another checkout.
                    let deadline = Date().addingTimeInterval(10)
                    while active, let id = transaction.transactionIdentifier,
                          !removedTransactions.contains(id), Date() < deadline {
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                    completeCheckout(.success("Coins added to your wallet."), productID: productID)
                }
            } catch {
                completeCheckout(.failure(error), productID: productID)
            }
        case .failed:
            SKPaymentQueue.default().finishTransaction(transaction)
            if (transaction.error as? SKError)?.code == .paymentCancelled {
                completeCheckout(.success("Purchase canceled."), productID: productID)
            } else {
                completeCheckout(.failure(AppFailure("The purchase could not be completed. Please try again.")), productID: productID)
            }
        case .deferred:
            completeCheckout(.success("Waiting for purchase approval."), productID: productID)
        case .purchasing: break
        case .restored:
            // Consumable balances are persisted locally, never restored as new credits.
            SKPaymentQueue.default().finishTransaction(transaction)
        @unknown default: break
        }
    }

    private func deliver(_ transaction: SKPaymentTransaction) async throws -> Bool {
        let key = transaction.transactionIdentifier ?? transaction.payment.productIdentifier
        do {
            let credited = try await creditVerifiedTransaction(transaction)
            failedTransactions.remove(key)
            notifyChange()
            return credited
        } catch {
            guard active else { throw error }
            failedTransactions.insert(key); notifyChange()
            let failure = error as NSError
            Self.log.error("StoreKit 1 delivery failed: \(failure.domain, privacy: .public) \(failure.code)")
            throw AppFailure("Your purchase could not be added yet. Please retry purchases.")
        }
    }
    private func creditVerifiedTransaction(_ transaction: SKPaymentTransaction) async throws -> Bool {
        guard active, transaction.transactionState == .purchased,
              transaction.payment.applicationUsername.flatMap(UUID.init(uuidString:)) == account,
              let transactionID = transaction.transactionIdentifier, !transactionID.isEmpty,
              let pack = CoinPack.all.first(where: { $0.productID == transaction.payment.productIdentifier }),
              transaction.payment.quantity > 0 else { throw AppFailure("This transaction could not be credited to your wallet.") }
        let id = "apple:\(transactionID)"
        // Previously committed StoreKit 1 and StoreKit 2 identifiers share the same durable namespace.
        if ledger.entries.contains(where: { $0.id == id }) {
            SKPaymentQueue.default().finishTransaction(transaction)
            return false
        }
        if Bundle.main.appStoreReceiptURL.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            let refresh = StoreRequest()
            _ = try await refresh.perform(SKReceiptRefreshRequest())
        }
        let receipt = try await AppReceipt.local
        guard accepts(receipt.environment), receipt.bundleIdentifier == Bundle.main.bundleIdentifier,
              case .valid = await receipt.validate(),
              let purchase = receipt.purchases.first(where: { $0.transactionIdentifier == transactionID }),
              purchase.productIdentifier == pack.productID, purchase.quantity == transaction.payment.quantity,
              purchase.cancellationDate == nil, purchase.subscriptionExpirationDate == nil,
              purchase.productType == .consumable || purchase.productType == .unknown,
              active, !Task.isCancelled else { throw AppFailure("This transaction could not be verified.") }
        // Recheck after asynchronous receipt validation so overlapping callbacks cannot double-credit.
        let credited = !ledger.entries.contains(where: { $0.id == id })
        if credited {
            let (amount, overflow) = pack.coins.multipliedReportingOverflow(by: purchase.quantity)
            guard !overflow else { throw AppFailure("The coin amount could not be saved.") }
            var next = ledger
            try next.credit(id: id, amount: amount)
            try persist(next)
        }
        SKPaymentQueue.default().finishTransaction(transaction)
        return credited
    }
    private func accepts(_ environment: InAppReceiptPayload.Environment) -> Bool {
        localStoreKit ? environment == .xcode : environment == .sandbox || environment == .productionSandbox || environment == .production
    }
    func unlock(_ course: Course) throws {
        guard active else { throw AppFailure("Log in to continue.") }
        var next = ledger; try next.unlock(course); try persist(next)
    }
    private func persist(_ next: WalletLedger) throws {
        try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        ledger = next
        notifyChange()
    }
    private func notifyChange() { NotificationCenter.default.post(name: .walletChanged, object: self) }
}

extension Notification.Name { static let walletChanged = Notification.Name("Vava.WalletChanged") }
