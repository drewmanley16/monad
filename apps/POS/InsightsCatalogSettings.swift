import SwiftUI
import Charts

// MARK: - Insights

struct InsightsView: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Insights", subtitle: "Real-time revenue and settlement performance on Monad.")

                let cumulative = cumulativeRevenue
                HStack(spacing: 12) {
                    StatTile(title: "Gross volume", value: "\(MON.format(store.grossVolume, maxFraction: 3)) MON", icon: "banknote.fill",
                             color: T.violet, spark: cumulative.map(\.1))
                    StatTile(title: "Payments", value: "\(store.sales.count)", icon: "creditcard.fill", color: T.magenta)
                    StatTile(title: "Avg. ticket", value: "\(MON.format(store.avgTicket, maxFraction: 3)) MON", icon: "cart.fill", color: T.pink)
                    StatTile(title: "Tips", value: "\(MON.format(store.tipsTotal, maxFraction: 3)) MON", icon: "heart.fill", color: T.flame)
                    StatTile(title: "Avg. finality", value: store.avgFinalityMs.map { "\($0) ms" } ?? "—", icon: "bolt.fill", color: T.mint,
                             spark: store.sales.compactMap(\.finalizedMs).reversed().map(Double.init))
                }

                HStack(alignment: .top, spacing: 14) {
                    revenueChart.frame(maxWidth: .infinity)
                    liveBlocks.frame(width: 320)
                }

                HStack(alignment: .top, spacing: 14) {
                    topProducts.frame(maxWidth: .infinity)
                    finalityHistogram.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
        .scrollIndicators(.never)
    }

    private var cumulativeRevenue: [(Date, Double)] {
        var acc = 0.0
        return store.sales.sorted { $0.date < $1.date }.map { s in acc += Double(s.event.amount) / 1e18; return (s.date, acc) }
    }

    private var revenueChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Revenue").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("cumulative MON").font(.system(size: 11.5)).foregroundStyle(T.faint)
            }
            let data = cumulativeRevenue
            if data.count < 2 {
                empty("Make a couple of sales to see the curve")
            } else {
                Chart(data, id: \.0) { d in
                    AreaMark(x: .value("Time", d.0), y: .value("MON", d.1))
                        .foregroundStyle(LinearGradient(colors: [T.magenta.opacity(0.45), T.violet.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", d.0), y: .value("MON", d.1))
                        .foregroundStyle(T.fire).lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Time", d.0), y: .value("MON", d.1)).foregroundStyle(.white).symbolSize(14)
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(T.faint); AxisGridLine().foregroundStyle(T.stroke) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(T.faint); AxisGridLine().foregroundStyle(T.stroke) } }
                .frame(height: 230)
            }
        }
        .panel(radius: 16)
    }

    private var liveBlocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live blocks").font(.system(size: 15, weight: .semibold))
                Spacer()
                Circle().fill(store.connected ? T.mint : T.flame).frame(width: 7, height: 7).shadow(color: T.mint, radius: 4)
            }
            ForEach(store.recentBlocks) { b in
                HStack {
                    Text("#\(b.number.formatted())").font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    Text("\(b.gas.formatted()) gas").font(.system(size: 11, design: .monospaced)).foregroundStyle(T.faint)
                    Spacer()
                    StatePill(state: b.state)
                }
                .padding(.vertical, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.recentBlocks)
        .panel(radius: 16)
    }

    private var topProducts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top items").font(.system(size: 15, weight: .semibold))
            let items = Array(store.topProducts.prefix(6))
            if items.isEmpty { empty("No item sales yet") } else {
                Chart(items, id: \.name) { p in
                    BarMark(x: .value("Revenue", p.revenue), y: .value("Item", "\(p.emoji) \(p.name)"))
                        .foregroundStyle(T.fire).cornerRadius(5)
                        .annotation(position: .trailing) {
                            Text("\(p.qty) sold").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(T.dim)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(T.text) } }
                .frame(height: CGFloat(items.count) * 34 + 10)
            }
        }
        .panel(radius: 16)
    }

    private var finalityHistogram: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Time to finality").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("from first sighting").font(.system(size: 11.5)).foregroundStyle(T.faint)
            }
            let ms = store.sales.compactMap(\.finalizedMs).filter { $0 > 0 }
            if ms.isEmpty { empty("Waiting for finalized payments") } else {
                let buckets = stride(from: 0, to: 2000, by: 250).map { lo in
                    (label: "\(lo)–\(lo + 250)", count: ms.filter { $0 >= lo && $0 < lo + 250 }.count)
                }
                Chart(buckets, id: \.label) { b in
                    BarMark(x: .value("ms", b.label), y: .value("Payments", b.count))
                        .foregroundStyle(LinearGradient(colors: [T.mint, T.mint.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(4)
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(T.faint) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(T.faint); AxisGridLine().foregroundStyle(T.stroke) } }
                .frame(height: 200)
            }
        }
        .panel(radius: 16)
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(T.faint).frame(maxWidth: .infinity, minHeight: 160)
    }
}

// MARK: - Catalog

struct CatalogView: View {
    @EnvironmentObject var store: POSStore
    @State private var editing: Product?
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Catalog", subtitle: "\(store.catalog.count) items across \(Set(store.catalog.map(\.category)).count) categories")
                    Spacer()
                    Button { creating = true } label: { Label("New item", systemImage: "plus").padding(.horizontal, 16).frame(height: 38) }
                        .buttonStyle(FireButton())
                        .keyboardShortcut("n", modifiers: .command)
                }
                ForEach(ProductCategory.allCases) { cat in
                    let items = store.catalog.filter { $0.category == cat }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: cat.icon).foregroundStyle(cat.color)
                                Text(cat.rawValue).font(.system(size: 14, weight: .semibold))
                                Text("\(items.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(T.faint)
                            }
                            .padding(.bottom, 10)
                            VStack(spacing: 0) {
                                ForEach(items) { p in
                                    HStack(spacing: 14) {
                                        Text(p.emoji).font(.system(size: 22)).frame(width: 40, height: 40)
                                            .background(cat.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                        Text(p.name).font(.system(size: 13.5, weight: .semibold))
                                        Spacer()
                                        Text("\(store.unitsSold(p)) sold").font(.system(size: 12)).foregroundStyle(T.faint).frame(width: 70, alignment: .trailing)
                                        Text("\(MON.format(p.price, maxFraction: 4)) MON").font(.system(size: 13, weight: .medium, design: .monospaced))
                                            .frame(width: 110, alignment: .trailing)
                                        Button { editing = p } label: { Image(systemName: "pencil") }.buttonStyle(GhostButton())
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    if p.id != items.last?.id { Rectangle().fill(T.stroke).frame(height: 1).padding(.leading, 68) }
                                }
                            }
                            .panel(radius: 14, padding: 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { p in ProductEditor(product: p).environmentObject(store) }
        .sheet(isPresented: $creating) { ProductEditor(product: nil).environmentObject(store) }
    }
}

struct ProductEditor: View {
    @EnvironmentObject var store: POSStore
    @Environment(\.dismiss) private var dismiss
    let product: Product?
    @State private var name = ""
    @State private var emoji = "✨"
    @State private var category: ProductCategory = .coffee
    @State private var price = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(product == nil ? "New item" : "Edit item").font(.system(size: 20, weight: .bold))
            HStack(spacing: 14) {
                TextField("", text: $emoji).font(.system(size: 34)).multilineTextAlignment(.center)
                    .frame(width: 68, height: 68).textFieldStyle(.plain)
                    .background(category.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                VStack(spacing: 10) {
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                    TextField("Price (MON)", text: $price).textFieldStyle(.roundedBorder)
                }
            }
            Picker("Category", selection: $category) {
                ForEach(ProductCategory.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                if let product {
                    Button("Delete", role: .destructive) { store.remove(product); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(product == nil ? "Add item" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || MON.parse(price) == nil)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if let p = product { name = p.name; emoji = p.emoji; category = p.category; price = MON.format(p.price, maxFraction: 18) }
        }
    }

    private func save() {
        var p = Product(id: product?.id ?? UUID().uuidString, name, String(emoji.prefix(2)), category, price)
        if p.emoji.isEmpty { p.emoji = "✨" }
        store.upsert(p)
        dismiss()
    }
}

// MARK: - Settings

struct POSSettingsView: View {
    @EnvironmentObject var store: POSStore
    @State private var payoutDraft = ""
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Settings")
                group("Business") {
                    field("Business name") { TextField("", text: $store.merchantName).textFieldStyle(.roundedBorder).frame(width: 320) }
                }
                group("Payouts") {
                    field("Payout address") {
                        HStack {
                            TextField("0x…", text: $payoutDraft).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).frame(width: 400)
                                .onSubmit(save)
                            Button("Save", action: save).disabled(!isAddress(payoutDraft) || payoutDraft == store.payout)
                        }
                    }
                    Text("Payments settle straight to this address — no processor, no payout delay.").font(.system(size: 12)).foregroundStyle(T.faint)
                }
                group("Network") {
                    row("Chain", "\(Chain.name) · \(Chain.chainId)")
                    row("Settlement contract", Chain.monadPay)
                    row("Realtime feed", "monadNewHeads + monadLogs over WebSocket")
                    row("Tap discovery", "Bluetooth LE (RSSI ≥ \(TapLink.tapRSSI) dBm) + Bonjour")
                }
                group("Data") {
                    Button("Clear order history", role: .destructive) { confirmReset = true }
                    Text("Removes local order history only. On-chain payments are unaffected.").font(.system(size: 12)).foregroundStyle(T.faint)
                }
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .onAppear { payoutDraft = store.payout }
        .confirmationDialog("Clear all order history?", isPresented: $confirmReset) {
            Button("Clear", role: .destructive) { store.resetSales() }
        }
    }

    private func save() {
        guard isAddress(payoutDraft) else { return }
        store.payout = payoutDraft
        store.connect()
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(T.faint)
            VStack(alignment: .leading, spacing: 12) { content() }.frame(maxWidth: .infinity, alignment: .leading).panel(radius: 14)
        }
    }
    private func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack { Text(label).foregroundStyle(T.dim).frame(width: 140, alignment: .leading); c() }.font(.system(size: 13))
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(T.dim).frame(width: 160, alignment: .leading)
            Text(v).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
        }
        .font(.system(size: 13))
    }
}
