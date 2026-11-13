import UIKit

@MainActor final class WalletScreen: ListScreen {
    private var selected: CoinPack?
    private var status: String?
    private var purchasing = false
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

    override func refreshContent() async throws {
        do {
            try await context.wallet.refresh()
            status = nil
            draw()
        } catch {
            status = "Prices could not load. Pull down to try again."
            draw()
        }
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
        var sections: [UIView] = [Theme.card([summary]), Theme.label("Coin packs", size: 25, display: true)]
        if let status {
            sections.append(Theme.label(status, color: Theme.coral))
        } else if !wallet.paymentsAllowed {
            sections.append(
                Theme.label("In-app purchases are disabled on this device.", color: Theme.secondary))
        } else if !CoinPack.all.contains(where: { wallet.price(for: $0) != nil }) {
            sections.append(
                Theme.label(
                    "Coin packs are currently unavailable. Pull down to check again.", color: Theme.secondary))
        }
        let columns = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 3
        for start in stride(from: 0, to: CoinPack.all.count, by: columns) {
            let row = Theme.stack(spacing: 8, axis: .horizontal)
            row.distribution = .fillEqually
            for pack in CoinPack.all.dropFirst(start).prefix(columns) {
                let price = wallet.price(for: pack)
                let button = Theme.button(
                    "\(pack.coins.formatted()) coins\n\(price ?? "Unavailable")",
                    primary: selected?.id == pack.id
                ) { [weak self] in
                    self?.selected = pack
                    self?.draw()
                }
                button.isEnabled = price != nil && !purchasing && wallet.paymentsAllowed
                button.accessibilityTraits = selected?.id == pack.id ? [.button, .selected] : [.button]
                row.addArrangedSubview(button)
            }
            sections.append(row)
        }
        if let selected, let price = wallet.price(for: selected) {
            let checkout = Theme.button(purchasing ? "Opening store…" : "Buy for \(price)", primary: true) {
                [weak self] in
                self?.buy(selected, price: price)
            }
            checkout.isEnabled = !purchasing && !wallet.busy && wallet.paymentsAllowed
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
