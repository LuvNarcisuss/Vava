import StoreKit

// Captures real queue callbacks for replay; it never constructs or finishes a transaction.
@MainActor final class StoreKitTransactionRecorder: NSObject, SKPaymentTransactionObserver {
    private(set) var purchases: [SKPaymentTransaction] = []
    override init() { super.init(); SKPaymentQueue.default().add(self) }
    func stop() { SKPaymentQueue.default().remove(self) }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            self.purchases.append(contentsOf: transactions.filter { $0.transactionState == .purchased })
        }
    }
}
