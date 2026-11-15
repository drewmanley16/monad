import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var store: POSStore
    @State private var tab: Tab = .library

    enum Tab: String, CaseIterable { case library = "Library", keypad = "Keypad" }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Rule()
                switch tab {
                case .library: library
                case .keypad: KeypadView()
                }
            }
            .background(T.bg)
            VRule()
            TicketView().frame(width: 380).background(T.surface)
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 16) {
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(width: 200).labelsHidden()
            Spacer()
            if tab == .library {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.faint)
                    TextField("Search items", text: $store.search).textFieldStyle(.plain).frame(width: 160)
                }
                .font(T.sans(13))
                .padding(.horizontal, 10).frame(height: 30)
                .background(T.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
            }
        }
        .padding(.horizontal, 20).frame(height: 56)
        .background(T.surface)
        .overlay(alignment: .bottom) {
            EmptyView()
        }
        if tab == .library {
            Rule()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    catButton("All items", nil)
                    ForEach(ProductCategory.allCases) { c in catButton(c.rawValue, c) }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 46)
            .background(T.surface)
        }
    }

    private func catButton(_ title: String, _ cat: ProductCategory?) -> some View {
        let on = store.categoryFilter == cat
        return Button { store.categoryFilter = cat } label: {
            Text(title).font(T.sans(13, on ? .semibold : .regular)).fixedSize()
                .foregroundStyle(on ? T.text : T.dim)
                .padding(.horizontal, 10).frame(height: 30)
                .background(on ? Color.black.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var library: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach(store.visibleProducts) { p in
                    ItemTile(product: p, qty: store.cart[p.id] ?? 0, color: color(for: p)) { store.add(p) }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.never)
    }

    private func color(for p: Product) -> Color {
        let i = store.catalog.firstIndex(of: p) ?? 0
        return T.tiles[i % T.tiles.count]
    }
}

struct ItemTile: View {
    let product: Product
    let qty: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(T.tile)
                    if let img = ItemPicture.photo(for: product.name) {
                        Image(nsImage: img).resizable().scaledToFill().grayscale(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    } else {
                        Image(systemName: ItemPicture.symbol(for: product))
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color(red: 0.32, green: 0.32, blue: 0.32))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if qty > 0 {
                        Text("\(qty)").font(T.mono(13, .semibold)).foregroundStyle(.white)
                            .frame(minWidth: 24, minHeight: 24).background(T.text, in: Circle())
                            .padding(8)
                    }
                }
                .aspectRatio(1.25, contentMode: .fit)
                .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(T.sans(14, .medium)).lineLimit(1)
                    Text("\(MON.format(product.price, maxFraction: 4)) MON").font(T.mono(13)).foregroundStyle(T.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(T.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(qty > 0 ? T.text : T.rule, lineWidth: qty > 0 ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePress())
    }
}

struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
                Text(entry).font(T.mono(64, .semibold))
                Text("MON").font(T.sans(15)).foregroundStyle(T.dim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(110), spacing: 10), count: 3), spacing: 10) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { k in
                    Button { press(k) } label: {
                        Group {
                            if k == "⌫" { Image(systemName: "delete.left") } else { Text(k) }
                        }
                        .font(T.sans(26))
                        .frame(width: 110, height: 64)
                        .background(T.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.rule))
                    }
                    .buttonStyle(TilePress())
                }
            }
            Button {
                if let w = MON.parse(entry), w > 0 { store.customAmount = (store.customAmount ?? 0) + w; entry = "0" }
            } label: {
                Text("Add to sale").frame(width: 350, height: 48)
            }
            .buttonStyle(PrimaryAction(enabled: (MON.parse(entry) ?? 0) > 0))
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
                        ForEach(store.lines, id: \.product.id) { line in
                            row(name: line.product.name, qty: line.qty, amount: line.product.price * Wei(line.qty),
                                minus: { store.decrement(line.product) }, plus: { store.add(line.product) })
                        }
                        if let c = store.customAmount {
                            row(name: "Custom amount", qty: 1, amount: c, minus: { store.customAmount = nil }, plus: nil)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Tip").font(T.sans(14)).foregroundStyle(T.dim)
                    Spacer()
                    Picker("", selection: $store.tipPercent) {
                        Text("None").tag(0); Text("10%").tag(10); Text("15%").tag(15); Text("20%").tag(20)
                    }
                    .pickerStyle(.segmented).frame(width: 220).labelsHidden()
                }
                Rule()
                KV(k: "Subtotal", v: "\(MON.format(store.subtotal, maxFraction: 4)) MON")
                if store.tipPercent > 0 { KV(k: "Tip", v: "\(MON.format(store.tip, maxFraction: 4)) MON") }
                KV(k: "Total", v: "\(MON.format(store.total, maxFraction: 4)) MON", strong: true)

                Button { store.startCharge() } label: {
                    Text(store.total > 0 ? "Charge \(MON.format(store.total, maxFraction: 4)) MON" : "Charge")
                        .frame(maxWidth: .infinity).frame(height: 56)
                }
                .buttonStyle(PrimaryAction(enabled: store.total > 0))
                .disabled(store.total == 0)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(20)
        }
    }

    private func row(name: String, qty: Int, amount: Wei, minus: @escaping () -> Void, plus: (() -> Void)?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(T.sans(14, .medium))
                    if qty > 1 { Text("× \(qty)").font(T.mono(12)).foregroundStyle(T.dim) }
                }
                Spacer()
                HStack(spacing: 0) {
                    Button(action: minus) { Image(systemName: "minus").frame(width: 28, height: 28) }
                    if let plus { Button(action: plus) { Image(systemName: "plus").frame(width: 28, height: 28) } }
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.dim)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
                Text(MON.format(amount, maxFraction: 4)).font(T.mono(14)).frame(width: 64, alignment: .trailing)
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
            T.surface.ignoresSafeArea()
            switch store.charge {
            case .awaiting(let req): awaiting(req)
            case .paid(let req, let ev): paid(req, ev)
            case .idle: EmptyView()
            }
        }
    }

    private func awaiting(_ req: PaymentRequest) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.cancelCharge() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).frame(width: 36, height: 36) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                Spacer()
                Text(store.merchantName).font(T.sans(14, .medium)).foregroundStyle(T.dim)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20).padding(.top, 30)

            Spacer()
            VStack(spacing: 6) {
                Text("Total").font(T.sans(16)).foregroundStyle(T.dim)
                Text("\(MON.format(req.amount, maxFraction: 4)) MON").font(T.mono(72, .semibold))
                if !req.memo.isEmpty { Text(req.memo).font(T.sans(14)).foregroundStyle(T.dim) }
            }
            Spacer().frame(height: 48)
            HStack(spacing: 40) {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(T.bg).frame(width: 200, height: 200)
                        ContactlessRings(color: T.text, size: 180, icon: "wave.3.right")
                    }
                    Text("Hold phone near this Mac").font(T.sans(16, .semibold))
                    Text("Tapnad Wallet").font(T.sans(13)).foregroundStyle(T.dim)
                }
                Rectangle().fill(T.rule).frame(width: 1, height: 180)
                VStack(spacing: 14) {
                    Image(nsImage: qrNSImage(req.url.absoluteString)).interpolation(.none).resizable()
                        .frame(width: 176, height: 176).padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(T.rule))
                    Text("Scan to pay").font(T.sans(16, .semibold))
                    Text("Any Tapnad wallet").font(T.sans(13)).foregroundStyle(T.dim)
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

    private func paid(_ req: PaymentRequest, _ ev: PaidEvent) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(T.green).frame(width: 88, height: 88)
                Image(systemName: "checkmark").font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
            }
            .transition(.scale)
            Text("Payment approved").font(T.sans(28, .semibold)).padding(.top, 22)
            Text("\(MON.format(ev.amount, maxFraction: 4)) MON · from \(shortAddress(ev.payer))").font(T.mono(15)).foregroundStyle(T.dim).padding(.top, 6)

            VStack(spacing: 10) {
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
            .frame(width: 380)
            .card(padding: 18)
            .padding(.top, 28)
            .animation(.default, value: store.stateMs)

            Button { store.newSale() } label: { Text("New sale").frame(width: 380, height: 52) }
                .buttonStyle(PrimaryAction())
                .keyboardShortcut(.return, modifiers: [])
                .padding(.top, 20)
            Spacer()
        }
    }
}
