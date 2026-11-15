import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var store: POSStore
    @State private var showCustom = false
    @State private var customText = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Register", subtitle: "\(store.todaySales.count) sales today · \(MON.format(store.todaySales.reduce(0) { $0 + $1.event.amount }, maxFraction: 3)) MON")
                    Spacer()
                    searchField
                }
                categoryChips
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                        ForEach(store.visibleProducts) { p in
                            ProductTile(product: p, qty: store.cart[p.id] ?? 0) { store.add(p) }
                        }
                        customTile
                    }
                    .padding(.bottom, 24)
                    .animation(.snappy, value: store.visibleProducts.map(\.id))
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 28).padding(.top, 40)

            OrderPanel().frame(width: 370)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(T.faint)
            TextField("Search menu", text: $store.search).textFieldStyle(.plain).frame(width: 180)
            if !store.search.isEmpty {
                Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(T.faint) }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).frame(height: 34)
        .background(T.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(T.stroke))
    }

    private var categoryChips: some View {
        HStack(spacing: 8) {
            chip("All", icon: "sparkles", color: T.violet, selected: store.categoryFilter == nil) { store.categoryFilter = nil }
            ForEach(ProductCategory.allCases) { c in
                chip(c.rawValue, icon: c.icon, color: c.color, selected: store.categoryFilter == c) {
                    store.categoryFilter = store.categoryFilter == c ? nil : c
                }
            }
        }
    }

    private func chip(_ t: String, icon: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(selected ? .white : color)
                Text(t).font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 13).frame(height: 32)
            .foregroundStyle(selected ? .white : T.dim)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(color.opacity(0.85).gradient) : AnyShapeStyle(T.panel))
            )
            .overlay(Capsule().strokeBorder(selected ? .white.opacity(0.2) : T.stroke))
            .shadow(color: selected ? color.opacity(0.4) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }

    private var customTile: some View {
        Button { showCustom = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("✏️").font(.system(size: 30))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Custom amount").font(.system(size: 14, weight: .semibold))
                    Text(store.customAmount.map { "\(MON.format($0)) MON" } ?? "Any price").font(.system(size: 12.5)).foregroundStyle(T.dim)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(T.faint))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCustom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom amount").font(.headline)
                TextField("0.00 MON", text: $customText).textFieldStyle(.roundedBorder).frame(width: 200).onSubmit(applyCustom)
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
    @State private var bump = false

    var body: some View {
        Button {
            action()
            bump.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(product.emoji).font(.system(size: 30))
                        .frame(width: 50, height: 50)
                        .background(product.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(product.category.color.opacity(0.2)))
                        .phaseAnimator([1.0, 1.15, 1.0], trigger: bump) { v, s in v.scaleEffect(s) } animation: { _ in .snappy(duration: 0.14) }
                    Spacer()
                    if qty > 0 {
                        Text("\(qty)").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                            .frame(minWidth: 24, minHeight: 24).background(T.fire, in: Capsule())
                            .shadow(color: T.magenta.opacity(0.6), radius: 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("\(MON.format(product.price)) MON").font(.system(size: 12.5, weight: .medium, design: .monospaced)).foregroundStyle(T.dim)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .panel(radius: 16, padding: 16, glow: qty > 0 ? T.magenta : (hover ? product.category.color : nil))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(qty > 0 ? AnyShapeStyle(T.fire) : AnyShapeStyle(Color.clear), lineWidth: 1.5))
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.snappy(duration: 0.18), value: hover)
            .animation(.snappy, value: qty)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current order").font(.system(size: 17, weight: .bold))
                    Text(store.itemCount == 0 ? "Empty" : "\(store.itemCount) item\(store.itemCount == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(T.dim)
                }
                Spacer()
                if store.itemCount > 0 { Button("Clear") { store.clear() }.buttonStyle(GhostButton()) }
            }
            .padding(.horizontal, 22).padding(.top, 44).padding(.bottom, 14)

            if store.itemCount == 0 {
                Spacer()
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(T.violet.opacity(0.1)).frame(width: 84, height: 84)
                        Image(systemName: "cart.fill").font(.system(size: 28)).foregroundStyle(T.fire)
                    }
                    Text("Ring something up").font(.system(size: 15, weight: .semibold))
                    Text("Click items to build the order.\n⌘1–6 to switch sections.").font(.system(size: 12.5))
                        .foregroundStyle(T.dim).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.lines, id: \.product.id) { line in
                            HStack(spacing: 12) {
                                Text(line.product.emoji).font(.system(size: 20))
                                    .frame(width: 38, height: 38).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.product.name).font(.system(size: 13.5, weight: .semibold))
                                    Text("\(MON.format(line.product.price * Wei(line.qty))) MON").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(T.dim)
                                }
                                Spacer()
                                Stepperish(qty: line.qty, minus: { store.decrement(line.product) }, plus: { store.add(line.product) })
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                        if let c = store.customAmount {
                            HStack {
                                Text("✏️").font(.system(size: 20)).frame(width: 38, height: 38)
                                Text("Custom amount").font(.system(size: 13.5, weight: .semibold))
                                Spacer()
                                Text("\(MON.format(c)) MON").font(.system(size: 12.5, design: .monospaced))
                                Button { store.customAmount = nil } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(T.faint)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.never)
            }

            VStack(spacing: 14) {
                // tip
                VStack(alignment: .leading, spacing: 8) {
                    Text("TIP").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(T.faint)
                    HStack(spacing: 6) {
                        ForEach([0, 10, 15, 20], id: \.self) { p in
                            Button { withAnimation(.snappy) { store.tipPercent = p } } label: {
                                Text(p == 0 ? "None" : "\(p)%").font(.system(size: 12.5, weight: .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .foregroundStyle(store.tipPercent == p ? .white : T.dim)
                                    .background(store.tipPercent == p ? AnyShapeStyle(T.fire) : AnyShapeStyle(Color.white.opacity(0.05)),
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Rectangle().fill(T.stroke).frame(height: 1)
                line("Subtotal", store.subtotal)
                if store.tipPercent > 0 { line("Tip (\(store.tipPercent)%)", store.tip) }
                line("Network fee", nil, note: "Paid by customer")
                HStack(alignment: .firstTextBaseline) {
                    Text("Total").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(MON.format(store.total, maxFraction: 5)).font(.system(size: 32, weight: .bold, design: .rounded))
                        .contentTransition(.numericText()).foregroundStyle(T.text)
                    Text("MON").font(.system(size: 13, weight: .bold)).foregroundStyle(T.dim)
                }
                Button { store.startCharge() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wave.3.right").font(.system(size: 14, weight: .bold))
                        Text(store.total > 0 ? "Charge \(MON.format(store.total, maxFraction: 5)) MON" : "Charge")
                        Spacer()
                        Text("↩").font(.system(size: 13, weight: .bold)).opacity(0.7)
                    }
                    .padding(.horizontal, 18).frame(height: 54)
                }
                .buttonStyle(FireButton(enabled: store.total > 0))
                .disabled(store.total == 0)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
        }
        .background(T.panel.opacity(0.55))
        .overlay(alignment: .leading) { Rectangle().fill(T.stroke).frame(width: 1) }
        .animation(.snappy, value: store.total)
    }

    private func line(_ k: String, _ v: Wei?, note: String? = nil) -> some View {
        HStack {
            Text(k).foregroundStyle(T.dim)
            Spacer()
            if let v { Text("\(MON.format(v, maxFraction: 5)) MON").font(.system(size: 13, design: .monospaced)) }
            if let note { Text(note).foregroundStyle(T.faint) }
        }
        .font(.system(size: 13))
    }
}

struct Stepperish: View {
    let qty: Int
    let minus: () -> Void
    let plus: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 26, height: 26).contentShape(Rectangle()) }
            Text("\(qty)").font(.system(size: 12.5, weight: .bold, design: .monospaced)).frame(minWidth: 20)
            Button(action: plus) { Image(systemName: "plus").frame(width: 26, height: 26).contentShape(Rectangle()) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .heavy))
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(T.stroke))
    }
}

// MARK: - Charge takeover (full window)

struct ChargeTakeover: View {
    @EnvironmentObject var store: POSStore

    private var isPaid: Bool { if case .paid = store.charge { return true }; return false }

    var body: some View {
        ZStack {
            AuroraBackground(colors: isPaid
                ? [T.bg, T.mint.opacity(0.45), T.bg, Color.teal.opacity(0.4), T.bg, T.mint.opacity(0.3), T.bg, T.violet.opacity(0.25), T.bg]
                : [T.bg, T.violet.opacity(0.6), T.bg, T.magenta.opacity(0.5), T.bg, T.pink.opacity(0.4), T.bg, T.violet.opacity(0.35), T.bg])
            .animation(.easeInOut(duration: 0.8), value: isPaid)
            Color.black.opacity(0.25).ignoresSafeArea()

            switch store.charge {
            case .awaiting(let req): awaiting(req).transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .paid(let req, let ev): paid(req, ev).transition(.opacity.combined(with: .scale(scale: 1.03)))
            case .idle: EmptyView()
            }

            if isPaid { Confetti().ignoresSafeArea() }

            VStack {
                Spacer()
                ticker
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isPaid)
    }

    private func awaiting(_ req: PaymentRequest) -> some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Text(store.merchantName.uppercased()).font(.system(size: 12, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(MON.format(req.amount, maxFraction: 5)).font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("MON").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
                if !req.memo.isEmpty {
                    Text(req.memo).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }

            HStack(spacing: 48) {
                VStack(spacing: 14) {
                    ZStack {
                        ContactlessRings(color: .white, size: 250, icon: "iphone.radiowaves.left.and.right")
                    }
                    Text("Hold iPhone near this Mac").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(spacing: 14) {
                    Image(nsImage: qrNSImage(req.url.absoluteString)).interpolation(.none).resizable()
                        .frame(width: 150, height: 150).padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    Text("or scan to pay").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
            }

            Button { store.cancelCharge() } label: {
                Text("Cancel").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 20).frame(height: 34)
                    .background(.white.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private func paid(_ req: PaymentRequest, _ ev: PaidEvent) -> some View {
        VStack(spacing: 26) {
            SuccessCheck(size: 120)
            VStack(spacing: 8) {
                Text("Approved").font(.system(size: 52, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                HStack(spacing: 10) {
                    AddressAvatar(seed: ev.payer, size: 22)
                    Text("\(MON.format(ev.amount, maxFraction: 5)) MON from \(shortAddress(ev.payer))")
                        .font(.system(size: 16, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                }
            }

            HStack(spacing: 0) {
                ForEach(CommitState.timeline, id: \.self) { s in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(store.stateMs[s] != nil ? T.mint : Color.white.opacity(0.12)).frame(width: 34, height: 34)
                                .shadow(color: store.stateMs[s] != nil ? T.mint : .clear, radius: 10)
                            Image(systemName: store.stateMs[s] != nil ? "checkmark" : "ellipsis")
                                .font(.system(size: 13, weight: .heavy)).foregroundStyle(store.stateMs[s] != nil ? .black : .white.opacity(0.5))
                        }
                        Text(s.rawValue).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        Text(store.stateMs[s].map { "+\($0) ms" } ?? "—").font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65)).contentTransition(.numericText())
                    }
                    .frame(width: 150)
                    if s != .finalized {
                        Rectangle().fill(store.stateMs[CommitState.timeline[CommitState.timeline.firstIndex(of: s)! + 1]] != nil ? T.mint : .white.opacity(0.15))
                            .frame(width: 60, height: 2).offset(y: -30)
                    }
                }
            }
            .padding(.vertical, 22).padding(.horizontal, 28)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .animation(.spring(duration: 0.35), value: store.stateMs)

            HStack(spacing: 12) {
                Link(destination: URL(string: Chain.explorerTx + ev.txHash)!) {
                    Label("Block #\(ev.blockNumber.formatted())", systemImage: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                Button { store.newSale() } label: {
                    HStack(spacing: 8) { Text("New sale"); Text("↩").opacity(0.6) }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 24).frame(height: 40)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var ticker: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Circle().fill(T.mint).frame(width: 6, height: 6).shadow(color: T.mint, radius: 4)
                Text("MONAD TESTNET").font(.system(size: 10, weight: .heavy)).tracking(1.5)
            }
            Text("BLOCK \(store.blockNumber.formatted())").font(.system(size: 11, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText(value: Double(store.blockNumber)))
            Text("\(store.blockTimeMs ?? 0) MS BLOCKS").font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text("WATCHING monadLogs IN REAL TIME").font(.system(size: 11, weight: .semibold, design: .monospaced)).opacity(0.6)
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 18).frame(height: 34)
        .background(.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .padding(.bottom, 26)
        .animation(.snappy, value: store.blockNumber)
    }
}
