import SwiftUI

// MARK: - Speed comparison (approval screen)

struct SpeedCompare: View {
    let finalMs: Int?
    let proposedMs: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label2("Settled vs. typical")
            row("Tapnad on Monad", finalMs.map { "\($0 < 1000 ? "\($0) ms" : String(format: "%.1f s", Double($0) / 1000))" } ?? "…", bold: true)
            row("Card authorization", "~2 s")
            row("Card settlement", "1–3 days")
            row("Ethereum finality", "~13 min")
            Text("Finality measured live from the Proposed block. Card and Ethereum figures are typical published values.")
                .font(T.sans(11)).foregroundStyle(T.faint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ k: String, _ v: String, bold: Bool = false) -> some View {
        HStack {
            Text(k).font(T.sans(13, bold ? .semibold : .regular)).foregroundStyle(bold ? T.text : T.dim)
            Spacer()
            Text(v).font(T.mono(13, bold ? .semibold : .regular))
        }
    }
}

// MARK: - How it works

struct HowItWorks: View {
    @Environment(\.dismiss) private var dismiss
    private let steps: [(String, String, String)] = [
        ("cart", "Ring it up", "The register builds the order and publishes a payment request over Bluetooth (iPhone) or the local network."),
        ("iphone.radiowaves.left.and.right", "Tap", "The customer holds their iPhone to the Mac. The phone identifies its wallet, so loyalty rewards apply automatically."),
        ("faceid", "Approve", "Face ID unlocks a key that never leaves the phone. It signs a MonadPay transaction and broadcasts it."),
        ("bolt", "Proposed in ~300 ms", "The register streams Monad's monadLogs feed and shows Approved as soon as the block is proposed."),
        ("checkmark.seal", "Final in under a second", "Voted, then Finalized. Funds land in the merchant's wallet directly. No processor, no settlement delay."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("How Tapnad works").font(T.sans(22, .semibold))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(QuietAction()).keyboardShortcut(.defaultAction)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle().fill(T.bg).frame(width: 44, height: 44)
                        Image(systemName: s.0).font(.system(size: 17))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(i + 1). \(s.1)").font(T.sans(15, .semibold))
                        Text(s.2).font(T.sans(13)).foregroundStyle(T.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Rule()
            HStack(spacing: 24) {
                KV(k: "Chain", v: "Monad testnet")
                KV(k: "Contract", v: shortAddress(Chain.monadPay))
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(T.surface)
    }
}

// MARK: - Customer-facing display

struct CustomerDisplay: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        ZStack {
            GlassBackdrop()
            switch store.charge {
            case .idle: building
            case .awaiting(let req): pay(req)
            case .paid(_, let ev): thanks(ev)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.charge)
        .animation(.snappy, value: store.cart)
    }

    private var building: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.merchantName).font(T.sans(28, .semibold)).padding(.bottom, 24)
            if store.itemCount == 0 {
                Spacer()
                Text("Welcome").font(T.sans(56, .semibold))
                Text("Your order will appear here.").font(T.sans(18)).foregroundStyle(T.dim)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(store.cart) { l in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.qty > 1 ? "\(l.qty)× \(l.title)" : l.title).font(T.sans(22, .medium))
                                    if let d = l.detail { Text(d).font(T.sans(15)).foregroundStyle(T.dim) }
                                }
                                Spacer()
                                Text(Money.usd(l.total)).font(T.mono(22))
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                }
                Rule().padding(.vertical, 16)
                HStack(alignment: .firstTextBaseline) {
                    Text("Total").font(T.sans(26, .semibold))
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(Money.usd(store.total))").font(T.mono(36, .semibold)).contentTransition(.numericText())
                    }
                }
            }
        }
        .padding(48)
    }

    private func pay(_ req: PaymentRequest) -> some View {
        VStack(spacing: 22) {
            Text(store.parts.count > 1 ? "Payment \(store.currentPartIndex + 1) of \(store.parts.count)" : "Total due")
                .font(T.sans(20)).foregroundStyle(T.dim)
            Text("\(Money.usd(req.amount))").font(T.mono(68, .semibold))
            if let note = store.rewardNotice { Label(note, systemImage: "gift").font(T.sans(18, .medium)) }
            ContactlessRings(color: T.text, size: 200, icon: "wave.3.right")
            Text("Hold your phone near the register").font(T.sans(22, .semibold))
            Image(nsImage: qrNSImage(req.webURL.absoluteString)).interpolation(.none).resizable().frame(width: 120, height: 120)
            Text("or scan with your phone camera").font(T.sans(14)).foregroundStyle(T.dim)
        }
    }

    private func thanks(_ ev: PaidEvent) -> some View {
        let c = store.customer(ev.payer)
        return VStack(spacing: 18) {
            ZStack {
                Circle().fill(T.text).frame(width: 110, height: 110)
                Image(systemName: "checkmark").font(.system(size: 48, weight: .bold)).foregroundStyle(.white)
            }
            Text("Thank you!").font(T.sans(48, .semibold))
            Text("Order #\(store.lastOrderNumber ?? 0)").font(T.mono(22)).foregroundStyle(T.dim)
            if let c {
                HStack(spacing: 8) {
                    ForEach(0..<LoyaltyProgram.stampsForReward, id: \.self) { i in
                        Circle().fill(i < c.stamps ? T.text : .clear).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(i < c.stamps ? T.text : T.rule, lineWidth: 1.5))
                    }
                }
                .padding(.top, 8)
                Text(c.stamps == 0 && c.rewardsEarned > 0 ? "You earned a free drink!" : "\(LoyaltyProgram.stampsForReward - c.stamps) more for a free drink")
                    .font(T.sans(17)).foregroundStyle(T.dim)
            }
        }
    }
}

// MARK: - End-of-day close out

struct CloseOutSheet: View {
    @EnvironmentObject var store: POSStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let today = store.todaySales
        let gross = today.reduce(Wei(0)) { $0 + $1.event.amount }
        let refunds = today.filter { $0.refundTx != nil }.reduce(Wei(0)) { $0 + $1.event.amount }
        let tips = today.reduce(Wei(0)) { $0 + $1.tip }
        let orders = Set(today.map { $0.orderNumber.map(String.init) ?? $0.id }).count
        let items = today.flatMap { $0.lines ?? [] }
        let top = Dictionary(grouping: items, by: \.name).mapValues { $0.reduce(0) { $0 + $1.qty } }.sorted { $0.value > $1.value }.prefix(5)
        let finals = today.compactMap(\.finalizedMs)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Close out").font(T.sans(22, .semibold))
                Text(Date.now.formatted(date: .complete, time: .omitted)).font(T.sans(13)).foregroundStyle(T.dim)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(QuietAction()).keyboardShortcut(.defaultAction)
            }
            VStack(spacing: 9) {
                KV(k: "Gross sales", v: "\(Money.usd(gross))")
                KV(k: "Refunds", v: "−\(Money.usd(refunds))")
                KV(k: "Net sales", v: "\(Money.usd(gross - refunds))", strong: true)
                Rule()
                KV(k: "Tips", v: "\(Money.usd(tips))")
                KV(k: "Orders", v: "\(orders)")
                KV(k: "Payments", v: "\(today.count)")
                KV(k: "Items sold", v: "\(items.reduce(0) { $0 + $1.qty })")
                KV(k: "Avg. finality", v: finals.isEmpty ? "—" : "\(finals.reduce(0, +) / finals.count) ms")
            }
            .card()
            if !top.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label2("Top items")
                    ForEach(Array(top), id: \.key) { KV(k: $0.key, v: "\($0.value)") }
                }
                .card()
            }
            HStack {
                Spacer()
                Button("Copy summary") {
                    let text = "\(store.merchantName) close-out \(Date.now.formatted(date: .abbreviated, time: .omitted))\nNet \(Money.usd(gross - refunds)) · \(orders) orders · tips \(Money.usd(tips))"
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(QuietAction())
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(T.surface)
    }
}
