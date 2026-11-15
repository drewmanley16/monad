import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var store: POSStore
    @State private var showCustom = false
    @State private var customText = ""

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                catalog
                Divider()
                OrderPanel().frame(width: 360)
            }
            .blur(radius: store.charge == .idle ? 0 : 8)
            .allowsHitTesting(store.charge == .idle)

            if store.charge != .idle {
                Color.black.opacity(0.25).ignoresSafeArea().transition(.opacity)
                ChargeCard().transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.charge)
    }

    private var catalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Register").font(.system(size: 28, weight: .semibold))
                    Text("Tap items to add them to the order.").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    ForEach(Product.catalog) { p in ProductTile(product: p, qty: store.cart[p.id] ?? 0) { store.add(p) } }
                    customTile
                }
            }
            .padding(28)
        }
    }

    private var customTile: some View {
        Button { showCustom = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom amount").font(.headline)
                    Text(store.customAmount.map { "\(MON.format($0)) MON" } ?? "Any price").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCustom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom amount").font(.headline)
                TextField("0.00", text: $customText).textFieldStyle(.roundedBorder).frame(width: 200)
                    .onSubmit(applyCustom)
                HStack { Spacer(); Button("Add", action: applyCustom).keyboardShortcut(.defaultAction) }
            }
            .padding(16)
        }
    }

    private func applyCustom() {
        if let w = MON.parse(customText), w > 0 { store.customAmount = w }
        customText = ""; showCustom = false
    }
}

struct ProductTile: View {
    let product: Product
    let qty: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: product.symbol).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(product.tint)
                        .frame(width: 40, height: 40)
                        .background(product.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    if qty > 0 {
                        Text("\(qty)").font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22).background(Brand.indigo, in: Capsule())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.headline)
                    Text("\(MON.format(product.price)) MON").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: 14)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(qty > 0 ? Brand.indigo.opacity(0.6) : .clear, lineWidth: 1.5))
            .scaleEffect(hover ? 1.015 : 1)
            .animation(.snappy(duration: 0.18), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Order panel

struct OrderPanel: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Current Order").font(.title3.weight(.semibold))
                Spacer()
                if store.itemCount > 0 {
                    Button("Clear") { store.clear() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(20)

            if store.itemCount == 0 {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "cart").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text("No items yet").font(.headline)
                    Text("Add something from the catalog.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.lines, id: \.product.id) { line in
                            HStack(spacing: 12) {
                                Image(systemName: line.product.symbol).foregroundStyle(line.product.tint)
                                    .frame(width: 30, height: 30)
                                    .background(line.product.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.product.name).font(.callout.weight(.medium))
                                    Text("\(MON.format(line.product.price)) each").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Stepperish(qty: line.qty, minus: { store.decrement(line.product) }, plus: { store.add(line.product) })
                            }
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        if let c = store.customAmount {
                            HStack {
                                Text("Custom amount").font(.callout.weight(.medium))
                                Spacer()
                                Text("\(MON.format(c)) MON").monospacedDigit()
                                Button { store.customAmount = nil } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                Divider()
                HStack {
                    Text("Subtotal").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(MON.format(store.total, maxFraction: 6)) MON").monospacedDigit()
                }
                HStack {
                    Text("Network fee").foregroundStyle(.secondary)
                    Spacer()
                    Text("Paid by customer").foregroundStyle(.secondary)
                }
                .font(.callout)
                HStack(alignment: .firstTextBaseline) {
                    Text("Total").font(.headline)
                    Spacer()
                    Text(MON.format(store.total, maxFraction: 6)).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("MON").font(.headline).foregroundStyle(.secondary)
                }
                Button { store.startCharge() } label: {
                    HStack {
                        Image(systemName: "wave.3.right")
                        Text("Charge \(MON.format(store.total, maxFraction: 6)) MON")
                    }
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(store.total > 0 ? Brand.indigo : Color.secondary.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.total == 0)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
        }
        .background(Color.primary.opacity(0.02))
        .animation(.snappy, value: store.total)
    }
}

struct Stepperish: View {
    let qty: Int
    let minus: () -> Void
    let plus: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 26, height: 26) }
            Text("\(qty)").font(.callout.monospacedDigit().weight(.semibold)).frame(minWidth: 22)
            Button(action: plus) { Image(systemName: "plus").frame(width: 26, height: 26) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .bold))
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

// MARK: - Charge card (awaiting tap / approved)

struct ChargeCard: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        VStack(spacing: 0) {
            switch store.charge {
            case .awaiting(let req): awaiting(req)
            case .paid(let req, let ev): paid(req, ev)
            case .idle: EmptyView()
            }
        }
        .frame(width: 560)
        .padding(36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.2), radius: 40, y: 20)
    }

    private func awaiting(_ req: PaymentRequest) -> some View {
        VStack(spacing: 22) {
            Text(store.merchantName.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MON.format(req.amount, maxFraction: 6)).font(.system(size: 64, weight: .semibold)).monospacedDigit()
                Text("MON").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
            }
            if !req.memo.isEmpty { Text(req.memo).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center) }

            HStack(spacing: 36) {
                VStack(spacing: 10) {
                    ContactlessRings(color: Brand.indigo, size: 190)
                    Text("Tap iPhone here").font(.headline)
                }
                VStack(spacing: 10) {
                    Image(nsImage: qrNSImage(req.url.absoluteString)).interpolation(.none).resizable()
                        .frame(width: 130, height: 130).padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Text("or scan").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for payment · watching Monad in real time").font(.callout).foregroundStyle(.secondary)
            }
            Button("Cancel") { store.cancelCharge() }.keyboardShortcut(.cancelAction).controlSize(.large)
        }
    }

    private func paid(_ req: PaymentRequest, _ ev: PaidEvent) -> some View {
        VStack(spacing: 22) {
            SuccessCheck(size: 96)
            VStack(spacing: 6) {
                Text("Approved").font(.system(size: 30, weight: .semibold))
                Text("\(MON.format(ev.amount, maxFraction: 6)) MON from \(shortAddress(ev.payer))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            CommitTimeline(rows: CommitState.timeline.map {
                .init(id: $0.rawValue, title: $0.rawValue, subtitle: $0.blurb, ms: store.stateMs[$0])
            })
            .surface()
            HStack {
                Link(destination: URL(string: Chain.explorerTx + ev.txHash)!) {
                    Label("Block #\(ev.blockNumber.formatted()) · View transaction", systemImage: "arrow.up.right")
                }
                .font(.callout)
                Spacer()
                Button { store.newSale() } label: {
                    Text("New Sale").font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 22).frame(height: 40)
                        .background(Brand.indigo, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }
}
