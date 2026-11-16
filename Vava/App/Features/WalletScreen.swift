import UIKit

@MainActor final class WalletScreen: ListScreen {
    private var selected: CoinPack?
    private var status: String?
    private var purchasing = false
    private var loadingPrices = false
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Wallet"
        NotificationCenter.default.addObserver(
            self, selector: #selector(walletChanged),
            name: .walletChanged, object: context.wallet)
        draw()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !started else {
            draw()
            return
        }
        started = true
        perform { try await self.refreshContent() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded,
            previousTraitCollection?.preferredContentSizeCategory
                != traitCollection.preferredContentSizeCategory
        {
            draw()
        }
    }

    override func refreshContent() async throws {
        loadingPrices = true
        status = nil
        draw()
        defer {
            loadingPrices = false
            if let selected, context.wallet.price(for: selected) == nil { self.selected = nil }
            draw()
        }
        await context.wallet.retryPendingPurchases()
        do {
            try await context.wallet.refresh()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            status = "Prices could not load. Pull down to try again."
        }
    }

    override var refreshCompletionMessage: String? {
        guard status == nil, !loadingPrices, !context.wallet.hasPurchaseIssue, context.wallet.paymentsAllowed,
            CoinPack.all.contains(where: { context.wallet.price(for: $0) != nil })
        else { return nil }
        return "Prices updated"
    }

    @objc private func walletChanged() { draw() }

    private func draw() {
        let wallet = context.wallet
        let value = Theme.label(wallet.ledger.balance.formatted(), size: 44, display: true, color: Theme.lime)
        let icon = UIImageView(image: UIImage(named: "icon-coin"))
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let summary = Theme.stack(
            [icon, Theme.stack([Theme.label("COIN BALANCE", size: 13, color: Theme.secondary), value])],
            axis: .horizontal)
        var sections: [UIView] = [Theme.card([summary])]
        if wallet.hasPurchaseIssue {
            let retry = Theme.button(wallet.retryingPurchases ? "Checking purchases…" : "Retry purchases") {
                [weak self] in
                guard let self else { return }
                self.perform { await self.context.wallet.retryPendingPurchases() }
            }
            retry.isEnabled = !wallet.retryingPurchases && !purchasing && !wallet.busy
            sections.append(
                Theme.card([
                    Theme.label("Purchase needs attention", size: 22, display: true),
                    Theme.label("Some purchases could not be added to your wallet. Retry to check them again."),
                    retry,
                ]))
        }
        sections.append(Theme.label("Coin packs", size: 25, display: true))
        let packs = CoinPack.all
        let availableCount = packs.filter { wallet.price(for: $0) != nil }.count
        let awaitingPrices = !started || loadingPrices
        let canBuy =
            !awaitingPrices && !purchasing && !wallet.busy && !wallet.retryingPurchases
            && wallet.paymentsAllowed
        if let status {
            sections.append(Theme.label(status, color: Theme.coral))
        } else if !wallet.paymentsAllowed {
            sections.append(
                Theme.label("In-app purchases are currently unavailable.", color: Theme.secondary))
        } else if awaitingPrices {
            sections.append(Theme.label("Loading prices…", color: Theme.secondary))
        } else if availableCount == 0 {
            sections.append(
                Theme.label(
                    "Coin packs are currently unavailable. Pull down to check again.", color: Theme.secondary))
        } else if availableCount < packs.count {
            sections.append(
                Theme.label(
                    "Some coin packs are unavailable. Pull down to check again.", color: Theme.secondary))
        }
        let columns = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 3
        for start in stride(from: 0, to: packs.count, by: columns) {
            let row = Theme.stack(spacing: 8, axis: .horizontal)
            row.distribution = .fillEqually
            for pack in packs.dropFirst(start).prefix(columns) {
                let price = wallet.price(for: pack)
                let quantity = pack.coins.formatted()
                let offer = price ?? (awaitingPrices ? "Loading…" : "Unavailable")
                let isSelected = price != nil && selected?.id == pack.id
                let button = Theme.button(
                    "\(quantity)\n\(offer)", primary: isSelected
                ) { [weak self] in
                    self?.selected = pack
                    self?.draw()
                }
                button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
                button.isEnabled = price != nil && canBuy
                button.accessibilityLabel = "\(quantity) coins"
                button.accessibilityValue = offer
                if isSelected { button.accessibilityTraits.insert(.selected) }
                row.addArrangedSubview(button)
            }
            sections.append(row)
        }
        if let selected, let price = wallet.price(for: selected) {
            let checkout = Theme.button(purchasing ? "Opening store…" : "Buy for \(price)", primary: true) {
                [weak self] in
                self?.buy(selected, price: price)
            }
            checkout.isEnabled = canBuy
            sections.append(checkout)
        }
        sections.append(Theme.label("Activity", size: 25, display: true))
        if wallet.ledger.entries.isEmpty {
            sections.append(Theme.card([Theme.label("No wallet activity yet.", color: Theme.secondary)]))
        }
        for entry in wallet.ledger.entries {
            let amount = entry.amount > 0 ? "+\(entry.amount.formatted())" : entry.amount.formatted()
            sections.append(
                Theme.card([
                    Theme.label("\(entry.title)  ·  \(amount) coins", display: true),
                    Theme.label(
                        entry.date.formatted(date: .abbreviated, time: .shortened), color: Theme.secondary),
                ]))
        }
        render(sections)
    }

    private func buy(_ pack: CoinPack, price: String) {
        guard !purchasing else { return }
        purchasing = true
        draw()
        perform {
            defer {
                self.purchasing = false
                self.draw()
            }
            let message = try await self.context.wallet.buy(pack, price: price)
            self.show("Wallet", message: message)
        }
    }
}
