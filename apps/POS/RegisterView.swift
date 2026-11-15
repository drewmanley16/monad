import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var store: POSStore
    @State private var customText = ""

    var body: some View {
        HStack(spacing: 0) {
            menu
            VRule()
            OrderColumn().frame(width: 360)
        }
    }

    // MARK: Menu — a typeset list, grouped by category

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(T.faint)
                TextField("Search", text: $store.search).textFieldStyle(.plain).font(T.sans(13))
                Spacer()
                Text("\(store.todaySales.count) sales today").font(T.mono(12)).foregroundStyle(T.faint)
            }
            .padding(.horizontal, 28).frame(height: 44)
            Rule()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(ProductCategory.allCases) { cat in
                        let items = store.visibleProducts.filter { $0.category == cat }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Label2(cat.rawValue).padding(.bottom, 8)
                                ForEach(items) { p in MenuRow(product: p, qty: store.cart[p.id] ?? 0) { store.add(p) } }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label2("Custom")
                        HStack(spacing: 8) {
                            TextField("Amount in MON", text: $customText).textFieldStyle(.plain).font(T.mono(13))
                                .padding(.horizontal, 10).frame(width: 180, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(T.rule))
                                .onSubmit(applyCustom)
                            Button("Add", action: applyCustom).buttonStyle(QuietAction())
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: 680, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }

    private func applyCustom() {
        if let w = MON.parse(customText), w > 0 { store.customAmount = w }
        customText = ""
    }
}

struct MenuRow: View {
    let product: Product
    let qty: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(qty > 0 ? "\(qty)×" : "")
                    .font(T.mono(12)).foregroundStyle(T.text).frame(width: 24, alignment: .leading)
                Text(product.name).font(T.sans(14)).foregroundStyle(T.text)
                Leader()
                Text(MON.format(product.price, maxFraction: 3)).font(T.mono(13)).foregroundStyle(qty > 0 ? T.text : T.dim)
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .background(hover ? T.hover : .clear, in: RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { hover = $0 }
    }
}

// MARK: - Order column

struct OrderColumn: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Order").font(T.sans(13, .medium))
                Spacer()
                if store.itemCount > 0 { Button("Clear") { store.clear() }.buttonStyle(QuietAction()) }
            }
            .padding(.horizontal, 22).frame(height: 44)
            Rule()

            if store.itemCount == 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No items.").font(T.sans(13)).foregroundStyle(T.dim)
                    Text("Click a menu item to add it.").font(T.sans(12)).foregroundStyle(T.faint)
                }
                .padding(22)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.lines, id: \.product.id) { line in
                            HStack(spacing: 10) {
                                Text(line.product.name).font(T.sans(13))
                                Spacer()
                                QtyControl(qty: line.qty, minus: { store.decrement(line.product) }, plus: { store.add(line.product) })
                                Text(MON.format(line.product.price * Wei(line.qty), maxFraction: 3)).font(T.mono(13))
                                    .frame(width: 60, alignment: .trailing)
                            }
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            Rule().padding(.leading, 22)
                        }
                        if let c = store.customAmount {
                            HStack {
                                Text("Custom").font(T.sans(13))
                                Spacer()
                                Button { store.customAmount = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                    .buttonStyle(.plain).foregroundStyle(T.faint)
                                Text(MON.format(c, maxFraction: 3)).font(T.mono(13)).frame(width: 60, alignment: .trailing)
                            }
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            Rule().padding(.leading, 22)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    Text("Tip").font(T.sans(13)).foregroundStyle(T.dim)
                    Spacer()
                    ForEach([0, 10, 15, 20], id: \.self) { p in
                        Button { store.tipPercent = p } label: {
                            Text(p == 0 ? "none" : "\(p)%").font(T.mono(12))
                                .foregroundStyle(store.tipPercent == p ? T.text : T.faint)
                                .underline(store.tipPercent == p)
                                .padding(.leading, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Rule()
                KV(k: "Subtotal", v: MON.format(store.subtotal, maxFraction: 4))
                if store.tipPercent > 0 { KV(k: "Tip \(store.tipPercent)%", v: MON.format(store.tip, maxFraction: 4)) }
                KV(k: "Total MON", v: MON.format(store.total, maxFraction: 4), strong: true)

                Button { store.startCharge() } label: {
                    HStack {
                        Text("Charge")
                        Spacer()
                        Text("↩").font(T.mono(12)).opacity(0.5)
                    }
                    .padding(.horizontal, 14).frame(height: 40)
                }
                .buttonStyle(PrimaryAction(enabled: store.total > 0))
                .disabled(store.total == 0)
                .keyboardShortcut(.return, modifiers: [])
                .padding(.top, 4)
            }
            .padding(22)
        }
    }
}

struct QtyControl: View {
    let qty: Int
    let minus: () -> Void
    let plus: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: minus) { Text("−").frame(width: 14) }
            Text("\(qty)").frame(minWidth: 14)
            Button(action: plus) { Text("+").frame(width: 14) }
        }
        .buttonStyle(.plain)
        .font(T.mono(12))
        .foregroundStyle(T.dim)
    }
}

// MARK: - Charge screen

struct ChargeScreen: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            switch store.charge {
            case .awaiting(let req): awaiting(req)
            case .paid(let req, let ev): paid(req, ev)
            case .idle: EmptyView()
            }
            VStack {
                Spacer()
                HStack(spacing: 14) {
                    Circle().fill(store.connected ? T.green : T.amber).frame(width: 5, height: 5)
                    Text("Monad testnet").foregroundStyle(T.dim)
                    Text("block \(store.blockNumber.formatted())")
                        .contentTransition(.numericText(value: Double(store.blockNumber)))
                    Text("\(store.blockTimeMs ?? 0)ms blocks").foregroundStyle(T.faint)
                }
                .font(T.mono(11.5))
                .animation(.default, value: store.blockNumber)
                .padding(.bottom, 28)
            }
        }
    }

    private func awaiting(_ req: PaymentRequest) -> some View {
        HStack(alignment: .center, spacing: 80) {
            VStack(alignment: .leading, spacing: 18) {
                Label2(store.merchantName)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(MON.format(req.amount, maxFraction: 4)).font(T.mono(84, .light))
                    Text("MON").font(T.mono(20)).foregroundStyle(T.dim)
                }
                if !req.memo.isEmpty {
                    Text(req.memo).font(T.sans(14)).foregroundStyle(T.dim).frame(maxWidth: 460, alignment: .leading)
                }
                Rule().frame(width: 460).padding(.vertical, 6)
                HStack(spacing: 10) {
                    PulseDot()
                    Text("Hold iPhone near this Mac, or scan.").font(T.sans(15))
                }
                Text("Waiting for the payment to appear on chain.").font(T.sans(12.5)).foregroundStyle(T.faint)
                Button("Cancel") { store.cancelCharge() }.buttonStyle(QuietAction()).keyboardShortcut(.cancelAction).padding(.top, 10)
            }
            Image(nsImage: qrNSImage(req.url.absoluteString)).interpolation(.none).resizable()
                .frame(width: 180, height: 180).padding(14)
                .background(T.text, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private func paid(_ req: PaymentRequest, _ ev: PaidEvent) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.green)
                Text("Paid").font(T.sans(15, .medium))
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(MON.format(ev.amount, maxFraction: 4)).font(T.mono(84, .light))
                Text("MON").font(T.mono(20)).foregroundStyle(T.dim)
            }
            Text("from \(ev.payer)").font(T.mono(12.5)).foregroundStyle(T.dim)

            Rule().frame(width: 520).padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 10) {
                Label2("Settlement")
                ForEach(CommitState.timeline, id: \.self) { s in
                    HStack(spacing: 10) {
                        Circle().fill(store.stateMs[s] != nil ? s.color : T.faint.opacity(0.4)).frame(width: 6, height: 6)
                        Text(s.rawValue).font(T.sans(14)).foregroundStyle(store.stateMs[s] != nil ? T.text : T.faint)
                        Leader()
                        Text(store.stateMs[s].map { "+\($0) ms" } ?? "…").font(T.mono(13))
                            .foregroundStyle(store.stateMs[s] != nil ? T.text : T.faint)
                            .contentTransition(.numericText())
                    }
                }
            }
            .frame(width: 520)
            .animation(.default, value: store.stateMs)

            HStack(spacing: 10) {
                Button { store.newSale() } label: {
                    HStack { Text("New sale"); Text("↩").font(T.mono(12)).opacity(0.5) }.padding(.horizontal, 16).frame(height: 34)
                }
                .buttonStyle(PrimaryAction())
                .keyboardShortcut(.return, modifiers: [])
                Link(destination: URL(string: Chain.explorerTx + ev.txHash)!) {
                    Text("Block \(ev.blockNumber.formatted()) ↗").font(T.mono(12))
                }
                .foregroundStyle(T.dim)
                .padding(.leading, 6)
            }
            .padding(.top, 10)
        }
    }
}

struct PulseDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(T.text).frame(width: 6, height: 6)
            .opacity(on ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(), value: on)
            .onAppear { on = true }
    }
}
