import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var store: POSStore
    @State private var tab: Tab = .library

    enum Tab: String, CaseIterable { case library = "Library", keypad = "Keypad" }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                header
                switch tab {
                case .library: library
                case .keypad: KeypadView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .glass(radius: 20)
            TicketView().frame(width: 370)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .glass(radius: 20, strong: true)
        }
        .overlay(alignment: .top) {
            if let msg = store.setupBanner {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(msg).font(T.sans(14, .medium))
                    Button { store.setupBanner = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 40)
                .background(T.text, in: Capsule())
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.setupBanner)
        .sheet(item: $store.optionsFor) { p in DrinkOptionsSheet(product: p).environmentObject(store) }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 16) {
            GlassSegments(options: Tab.allCases.map { ($0.rawValue, $0) }, selection: $tab).frame(width: 200)
            Spacer()
            if tab == .library {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.faint)
                    TextField("Search items", text: $store.search).textFieldStyle(.plain).frame(width: 160)
                }
                .font(T.sans(13))
                .padding(.horizontal, 10).frame(height: 30)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.8)))
            }
        }
        .padding(.horizontal, 18).frame(height: 56)
        if tab == .library {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    catButton("All items", nil)
                    ForEach(ProductCategory.allCases) { c in catButton(c.rawValue, c) }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 40)
        }
    }

    private func catButton(_ title: String, _ cat: ProductCategory?) -> some View {
        let on = store.categoryFilter == cat
        return Button { store.categoryFilter = cat } label: {
            Text(title).font(T.sans(13, on ? .semibold : .regular)).fixedSize()
                .foregroundStyle(on ? T.text : T.dim)
                .padding(.horizontal, 10).frame(height: 30)
                .background(on ? Color.white.opacity(0.8) : .clear, in: Capsule())
                .shadow(color: on ? .black.opacity(0.06) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var library: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach(store.visibleProducts) { p in
                    ItemTile(product: p, qty: store.qty(of: p)) { store.tap(p) }
                }
            }
            .padding(18)
        }
        .scrollIndicators(.never)
    }
}

struct ItemTile: View {
    let product: Product
    let qty: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(0.95, contentMode: .fit)
                .overlay {
                    ZStack {
                        LinearGradient(colors: [Color(white: 0.93), Color(white: 0.85)], startPoint: .top, endPoint: .bottom)
                        if let img = ItemPicture.photo(for: product.name) {
                            Image(nsImage: img).resizable().scaledToFill()
                        } else {
                            Image(systemName: ItemPicture.symbol(for: product))
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(Color(white: 0.35))
                                .offset(y: -18)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(product.name).font(T.sans(13.5, .semibold)).lineLimit(1)
                            Text(Money.usd(product.price)).font(T.mono(12.5)).foregroundStyle(T.dim)
                        }
                        Spacer(minLength: 4)
                        if product.category.hasOptions {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 10)).foregroundStyle(T.dim)
                        }
                    }
                    .foregroundStyle(T.text)
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.7)))
                    .padding(7)
                }
                .overlay(alignment: .topTrailing) {
                    if qty > 0 {
                        Text("\(qty)").font(T.mono(13, .semibold)).foregroundStyle(.white)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(Color.black.opacity(0.75), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.5)))
                            .padding(9)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let s = product.stock, s > 0, s <= 5 {
                        Text("\(s) left").font(T.sans(11, .semibold)).foregroundStyle(T.text)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(9)
                    }
                }
                .overlay {
                    if product.soldOut {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Text("Sold out").font(T.sans(14, .semibold)).foregroundStyle(T.text)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(qty > 0 ? AnyShapeStyle(Color.black.opacity(0.75)) : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom)),
                                      lineWidth: qty > 0 ? 2 : 1)
                )
                .shadow(color: .black.opacity(hover ? 0.16 : 0.08), radius: hover ? 18 : 10, y: hover ? 8 : 4)
                .scaleEffect(hover ? 1.02 : 1)
                .animation(.snappy(duration: 0.2), value: hover)
                .animation(.snappy, value: qty)
                .contentShape(Rectangle())
        }
        .buttonStyle(TilePress())
        .disabled(product.soldOut)
        .onHover { hover = $0 }
    }
}

struct QtyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.black.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Drink options

struct DrinkOptionsSheet: View {
    @EnvironmentObject var store: POSStore
    @Environment(\.dismiss) private var dismiss
    let product: Product
    @State private var opts = DrinkOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.name).font(T.sans(20, .semibold))
                Spacer()
                Text("\(Money.usd(product.price + opts.surcharge))").font(T.mono(17, .semibold))
                    .contentTransition(.numericText())
            }
            group("Size") {
                ForEach(DrinkOptions.Size.allCases, id: \.self) { s in
                    choice(s.rawValue, s == .large ? "+\(Money.usd(DrinkOptions.largeUp))" : nil, opts.size == s) { opts.size = s }
                }
            }
            group("Milk") {
                ForEach(DrinkOptions.Milk.allCases, id: \.self) { m in
                    choice(m.rawValue, m == .oat || m == .almond ? "+\(Money.usd(DrinkOptions.altMilk))" : nil, opts.milk == m) { opts.milk = m }
                }
            }
            if product.category == .coffee {
                group("Extras") {
                    choice("Extra shot", "+\(Money.usd(DrinkOptions.shot))", opts.extraShot) { opts.extraShot.toggle() }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(QuietAction()).keyboardShortcut(.cancelAction)
                Spacer()
                Button { store.add(product, options: opts); dismiss() } label: {
                    Text("Add to sale").padding(.horizontal, 20).frame(height: 38)
                }
                .buttonStyle(PrimaryAction())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(T.surface)
        .animation(.snappy, value: opts)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(title)
            HStack(spacing: 8) { c() }
        }
    }

    private func choice(_ title: String, _ price: String?, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(T.sans(13, on ? .semibold : .regular))
                if let price { Text(price).font(T.mono(11)).foregroundStyle(on ? .white.opacity(0.75) : T.faint) }
            }
            .foregroundStyle(on ? .white : T.text)
            .padding(.horizontal, 14).frame(minWidth: 80, minHeight: 44)
            .background(on ? T.text : T.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? T.text : T.rule))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keypad (custom amount)

struct KeypadView: View {
    @EnvironmentObject var store: POSStore
    @State private var entry = "0"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 4) {
                Text("$" + entry).font(T.mono(64, .semibold))
                Text("Custom amount").font(T.sans(15)).foregroundStyle(T.dim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(110), spacing: 10), count: 3), spacing: 10) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { k in
                    Button { press(k) } label: {
                        Group {
                            if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
                        }
                        .font(T.sans(26))
                        .frame(width: 110, height: 64)
                        .glass(radius: 16)
                    }
                    .buttonStyle(TilePress())
                }
            }
            Button {
                if let w = Money.parse(entry), w > 0 { store.customAmount = (store.customAmount ?? 0) + w; entry = "0" }
            } label: {
                Text("Add to sale").frame(width: 350, height: 48)
            }
            .buttonStyle(PrimaryAction(enabled: (Money.parse(entry) ?? 0) > 0))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func press(_ k: String) {
        switch k {
        case "⌫": entry = entry.count > 1 ? String(entry.dropLast()) : "0"
        case ".": if !entry.contains(".") { entry += "." }
        default: entry = entry == "0" ? k : entry + k
        }
        if (entry.split(separator: ".").dropFirst().first?.count ?? 0) > 6 { entry.removeLast() }
    }
}

// MARK: - Ticket

struct TicketView: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Current sale").font(T.sans(17, .semibold))
                Spacer()
                if store.itemCount > 0 {
                    Button("Clear") { store.clear() }.buttonStyle(.plain).font(T.sans(13, .medium)).foregroundStyle(T.dim)
                }
            }
            .padding(.horizontal, 20).frame(height: 56)
            Rule()

            if store.itemCount == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "cart").font(.system(size: 30)).foregroundStyle(T.faint)
                    Text("No items in sale").font(T.sans(14, .medium)).foregroundStyle(T.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.cart) { line in
                            row(name: line.title, detail: line.detail, qty: line.qty, amount: line.total,
                                minus: { store.decrement(line) }, plus: { store.increment(line) })
                        }
                        if let c = store.customAmount {
                            row(name: "Custom amount", detail: nil, qty: 1, amount: c, minus: { store.customAmount = nil }, plus: nil)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            VStack(spacing: 11) {
                control("Discount") {
                    GlassSegments(options: [("None", 0), ("10%", 10), ("25%", 25), ("Comp", 100)], selection: $store.discountPercent)
                }
                control("Tip") {
                    GlassSegments(options: [("None", 0), ("10%", 10), ("15%", 15), ("20%", 20)], selection: $store.tipPercent)
                }
                if POSStore.splitEnabled { control("Split") {
                    GlassSegments(options: [("No", 1), ("2", 2), ("3", 3), ("4", 4)], selection: $store.splitCount)
                } }
                Rule()
                KV(k: "Subtotal", v: "\(Money.usd(store.subtotal))")
                if store.discountPercent > 0 { KV(k: store.discountPercent == 100 ? "Comped" : "Discount \(store.discountPercent)%", v: "−\(Money.usd(store.discount))") }
                if store.taxPercent > 0 { KV(k: "Tax \(store.taxPercent.formatted())%", v: "\(Money.usd(store.tax))") }
                if store.tipPercent > 0 { KV(k: "Tip", v: "\(Money.usd(store.tip))") }
                KV(k: "Total", v: "\(Money.usd(store.total))", strong: true)
                if store.splitCount > 1 && store.total > 0 {
                    KV(k: "Each of \(store.splitCount)", v: "≈ \(Money.usd(store.total / Wei(store.splitCount)))")
                }

                Button { store.startCharge() } label: {
                    Text(chargeLabel).frame(maxWidth: .infinity).frame(height: 56)
                }
                .buttonStyle(PrimaryAction(enabled: store.total > 0))
                .disabled(store.total == 0)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
        }
    }

    private var chargeLabel: String {
        guard store.total > 0 else { return "Charge" }
        let base = "Charge \(Money.usd(store.total))"
        return store.splitCount > 1 ? base + " · \(store.splitCount) ways" : base
    }

    private func control<C: View>(_ label: String, @ViewBuilder _ picker: () -> C) -> some View {
        HStack {
            Text(label).font(T.sans(14)).foregroundStyle(T.dim)
            Spacer()
            picker().frame(width: 220)
        }
    }

    private func row(name: String, detail: String?, qty: Int, amount: Wei, minus: @escaping () -> Void, plus: (() -> Void)?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(T.sans(14, .medium))
                    if let detail { Text(detail).font(T.sans(12)).foregroundStyle(T.dim) }
                    if qty > 1 { Text("× \(qty)").font(T.mono(12)).foregroundStyle(T.dim) }
                }
                Spacer()
                HStack(spacing: 0) {
                    Button(action: minus) { Image(systemName: "minus").frame(width: 32, height: 30).contentShape(Rectangle()) }
                    if let plus {
                        Rectangle().fill(T.rule).frame(width: 1, height: 16)
                        Button(action: plus) { Image(systemName: "plus").frame(width: 32, height: 30).contentShape(Rectangle()) }
                    }
                }
                .buttonStyle(QtyPress()).font(.system(size: 11, weight: .bold)).foregroundStyle(T.text)
                .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.9)))
                Text(Money.usd(amount)).font(T.mono(14)).frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Rule().padding(.leading, 20)
        }
    }
}

// MARK: - Charge screen

struct ChargeScreen: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        ZStack {
            GlassBackdrop()
            switch store.charge {
            case .awaiting(let req): awaiting(req)
            case .paid(let req, let ev): paid(req, ev)
            case .idle: EmptyView()
            }
        }
    }

    private var isSplit: Bool { store.parts.count > 1 }

    private func awaiting(_ req: PaymentRequest) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.cancelCharge() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).frame(width: 36, height: 36) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(store.merchantName) · Order #\(store.lastOrderNumber ?? 0)").font(T.sans(14, .medium)).foregroundStyle(T.dim)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20).padding(.top, 30)

            Spacer()
            if isSplit { splitProgress.padding(.bottom, 28) }
            VStack(spacing: 6) {
                Text(isSplit ? "Payment \(store.currentPartIndex + 1) of \(store.parts.count)" : "Total").font(T.sans(16)).foregroundStyle(T.dim)
                Text("\(Money.usd(req.amount))").font(T.mono(72, .semibold))
                    .contentTransition(.numericText())
                if let note = store.rewardNotice {
                    Label(note, systemImage: "gift").font(T.sans(14, .medium)).padding(.top, 8)
                } else if let who = store.identifiedPayer {
                    Text("Phone connected · \(shortAddress(who))").font(T.mono(13)).foregroundStyle(T.dim).padding(.top, 8)
                }
            }
            .id(req.id)
            .transition(.push(from: .trailing))
            Spacer().frame(height: 48)
            HStack(spacing: 40) {
                VStack(spacing: 14) {
                    ContactlessRings(color: T.text, size: 180, icon: "wave.3.right")
                        .frame(width: 200, height: 200)
                        .glass(radius: 24, strong: true)
                    Text(isSplit ? "Next phone, tap here" : "Hold phone near this Mac").font(T.sans(16, .semibold))
                    Text("Tapnad Wallet").font(T.sans(13)).foregroundStyle(T.dim)
                }
                Rectangle().fill(T.rule).frame(width: 1, height: 180)
                VStack(spacing: 14) {
                    Image(nsImage: qrNSImage(req.webURL.absoluteString)).interpolation(.none).resizable()
                        .frame(width: 164, height: 164).padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white))
                        .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
                    Text("Scan to pay").font(T.sans(16, .semibold))
                    Text("Any phone camera, no app needed").font(T.sans(13)).foregroundStyle(T.dim)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for payment on Monad · block \(store.blockNumber.formatted())").font(T.mono(13)).foregroundStyle(T.dim)
            }
            .padding(.bottom, 30)
        }
    }

    private var splitProgress: some View {
        HStack(spacing: 10) {
            ForEach(Array(store.parts.enumerated()), id: \.offset) { i, p in
                let paid = i < store.paidParts.count
                let current = i == store.paidParts.count
                HStack(spacing: 8) {
                    Image(systemName: paid ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
                        .foregroundStyle(paid || current ? T.text : T.faint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Part \(i + 1)").font(T.sans(12, .semibold))
                        Text(paid ? shortAddress(store.paidParts[i].payer) : "\(Money.usd(p.amount))")
                            .font(T.mono(11)).foregroundStyle(T.dim)
                    }
                }
                .padding(.horizontal, 12).frame(height: 44)
                .background(current ? T.bg : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(current ? T.text : T.rule))
            }
        }
        .animation(.snappy, value: store.paidParts.count)
    }

    private func paid(_ req: PaymentRequest, _ ev: PaidEvent) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(T.text).frame(width: 88, height: 88)
                Image(systemName: "checkmark").font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
            }
            .transition(.scale)
            Text("Payment approved").font(T.sans(28, .semibold)).padding(.top, 22)
            Text("Order #\(store.lastOrderNumber ?? 0) · \(Money.usd(store.paidParts.reduce(Wei(0)) { $0 + $1.amount }))"
                 + (isSplit ? " · \(store.parts.count) payments" : " · from \(shortAddress(ev.payer))"))
                .font(T.mono(15)).foregroundStyle(T.dim).padding(.top, 6)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label2("Settlement")
                    ForEach(CommitState.timeline, id: \.self) { s in
                        HStack {
                            Circle().fill(store.stateMs[s] != nil ? s.color : T.rule).frame(width: 8, height: 8)
                            Text(s.rawValue).font(T.sans(14)).foregroundStyle(store.stateMs[s] != nil ? T.text : T.faint)
                            Spacer()
                            Text(store.stateMs[s].map { "+\($0) ms" } ?? "—").font(T.mono(14))
                                .foregroundStyle(store.stateMs[s] != nil ? T.text : T.faint)
                                .contentTransition(.numericText())
                        }
                    }
                    Rule()
                    HStack {
                        Text("Block").font(T.sans(14)).foregroundStyle(T.dim)
                        Spacer()
                        Link(ev.blockNumber.formatted(), destination: URL(string: Chain.explorerTx + ev.txHash)!).font(T.mono(14))
                    }
                }
                .frame(width: 300)
                .card(padding: 18)
                .animation(.default, value: store.stateMs)

                loyalty(ev.payer).frame(width: 260).card(padding: 18)
                SpeedCompare(finalMs: store.stateMs[.finalized], proposedMs: store.stateMs[.proposed]).frame(width: 260).card(padding: 18)
            }
            .padding(.top, 28)

            Button { store.newSale() } label: { Text("New sale").frame(width: 400, height: 52) }
                .buttonStyle(PrimaryAction())
                .keyboardShortcut(.return, modifiers: [])
                .padding(.top, 20)
            Spacer()
        }
    }

    @ViewBuilder private func loyalty(_ payer: String) -> some View {
        let c = store.customer(payer)
        let stamps = c?.stamps ?? 0
        let goal = LoyaltyProgram.stampsForReward
        VStack(alignment: .leading, spacing: 12) {
            Label2("Loyalty")
            Text(shortAddress(payer)).font(T.mono(13))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: goal / 2), alignment: .leading, spacing: 6) {
                ForEach(0..<goal, id: \.self) { i in
                    Circle().fill(i < stamps ? T.text : .clear).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(i < stamps ? T.text : T.rule))
                }
            }
            if let c, c.rewardsEarned > 0 && stamps == 0 {
                Text("Free drink earned. Comp it on their next order.").font(T.sans(12.5, .medium))
            } else {
                Text("\(goal - stamps) more drinks for a free one").font(T.sans(12.5)).foregroundStyle(T.dim)
            }
            Text("\(c?.visits ?? 1) visits · no sign-up, keyed to wallet").font(T.sans(11.5)).foregroundStyle(T.faint)
        }
    }
}
