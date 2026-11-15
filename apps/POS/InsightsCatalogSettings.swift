import SwiftUI
import Charts

// MARK: - Reports

struct InsightsView: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 36) {
                    Metric(label: "Gross volume", value: MON.format(store.grossVolume, maxFraction: 3))
                    Metric(label: "Orders", value: "\(store.sales.count)")
                    Metric(label: "Avg. ticket", value: MON.format(store.avgTicket, maxFraction: 3))
                    Metric(label: "Tips", value: MON.format(store.tipsTotal, maxFraction: 3))
                    Metric(label: "Avg. finality", value: store.avgFinalityMs.map { "\($0)ms" } ?? "—")
                    Spacer()
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
                Rule()

                HStack(alignment: .top, spacing: 0) {
                    section("Revenue, cumulative") { revenue }
                    VRule()
                    section("Blocks") { blocks }.frame(width: 320)
                }
                Rule()
                HStack(alignment: .top, spacing: 0) {
                    section("Items by revenue") { items }
                    VRule()
                    section("Time to finality") { finality }
                }
                Rule()
            }
        }
        .scrollIndicators(.never)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label2(title)
            c()
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var cumulative: [(Date, Double)] {
        var acc = 0.0
        return store.sales.sorted { $0.date < $1.date }.map { acc += Double($0.event.amount) / 1e18; return ($0.date, acc) }
    }

    private var axis: some AxisContent {
        AxisMarks { _ in
            AxisValueLabel().font(T.mono(10)).foregroundStyle(T.faint)
            AxisGridLine().foregroundStyle(T.rule)
        }
    }

    @ViewBuilder private var revenue: some View {
        let data = cumulative
        if data.count < 2 { empty } else {
            Chart(data, id: \.0) { d in
                LineMark(x: .value("Time", d.0), y: .value("MON", d.1))
                    .foregroundStyle(T.text).lineStyle(StrokeStyle(lineWidth: 1.25))
                    .interpolationMethod(.stepEnd)
            }
            .chartXAxis { axis }.chartYAxis { axis }
            .frame(height: 220)
        }
    }

    private var blocks: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(store.recentBlocks) { b in
                HStack(spacing: 10) {
                    Text(b.number.formatted()).font(T.mono(12.5))
                    Leader()
                    StateLabel(state: b.state)
                }
            }
            Sparkline(values: store.blockTimeHistory.isEmpty ? [0, 0] : store.blockTimeHistory).frame(height: 28).padding(.top, 8)
            Text("block time, last \(store.blockTimeHistory.count) blocks").font(T.sans(11)).foregroundStyle(T.faint)
        }
    }

    @ViewBuilder private var items: some View {
        let top = Array(store.topProducts.prefix(8))
        if top.isEmpty { empty } else {
            let mx = top.map(\.revenue).max() ?? 1
            VStack(alignment: .leading, spacing: 9) {
                ForEach(top, id: \.name) { p in
                    HStack(spacing: 12) {
                        Text(p.name).font(T.sans(13)).frame(width: 140, alignment: .leading).lineLimit(1)
                        GeometryReader { g in
                            Rectangle().fill(T.dim.opacity(0.5)).frame(width: max(2, g.size.width * p.revenue / mx), height: 6)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 14)
                        Text("\(p.qty)×").font(T.mono(12)).foregroundStyle(T.faint).frame(width: 34, alignment: .trailing)
                        Text(String(format: "%.3f", p.revenue)).font(T.mono(12.5)).frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder private var finality: some View {
        let ms = store.sales.compactMap(\.finalizedMs).filter { $0 > 0 }
        if ms.isEmpty { empty } else {
            let buckets = stride(from: 0, to: 2000, by: 250).map { lo in (label: "\(lo)", count: ms.filter { $0 >= lo && $0 < lo + 250 }.count) }
            Chart(buckets, id: \.label) { b in
                BarMark(x: .value("ms", b.label), y: .value("Orders", b.count), width: .ratio(0.55))
                    .foregroundStyle(T.dim.opacity(0.6))
            }
            .chartXAxis { axis }.chartYAxis { axis }
            .frame(height: 200)
            Text("milliseconds from first sighting to finalized").font(T.sans(11)).foregroundStyle(T.faint)
        }
    }

    private var empty: some View {
        Text("Not enough data yet.").font(T.sans(13)).foregroundStyle(T.faint).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }
}

// MARK: - Items

struct CatalogView: View {
    @EnvironmentObject var store: POSStore
    @State private var editing: Product?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(store.catalog.count) items").font(T.mono(12)).foregroundStyle(T.faint)
                Spacer()
                Button("New item") { creating = true }.buttonStyle(QuietAction()).keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 28).frame(height: 44)
            Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(ProductCategory.allCases) { cat in
                        let items = store.catalog.filter { $0.category == cat }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Label2(cat.rawValue).padding(.bottom, 8)
                                ForEach(items) { p in
                                    Button { editing = p } label: {
                                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                                            Text(p.name).font(T.sans(14))
                                            Leader()
                                            Text(p.stock.map { $0 == 0 ? "sold out" : "\($0) in stock" } ?? "").font(T.mono(12)).foregroundStyle(T.faint)
                                            Text("\(store.unitsSold(p)) sold").font(T.mono(12)).foregroundStyle(T.faint)
                                            Text(MON.format(p.price, maxFraction: 4)).font(T.mono(13)).frame(width: 64, alignment: .trailing)
                                            Text("edit").font(T.sans(12)).foregroundStyle(T.faint)
                                        }
                                        .padding(.vertical, 7)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .sheet(item: $editing) { p in ProductEditor(product: p).environmentObject(store) }
        .sheet(isPresented: $creating) { ProductEditor(product: nil).environmentObject(store) }
    }
}

struct ProductEditor: View {
    @EnvironmentObject var store: POSStore
    @Environment(\.dismiss) private var dismiss
    let product: Product?
    @State private var name = ""
    @State private var category: ProductCategory = .coffee
    @State private var price = ""
    @State private var stock = ""

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Price (MON)", text: $price)
            TextField("Stock (blank = don't track)", text: $stock)
            Picker("Category", selection: $category) {
                ForEach(ProductCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                if let product { Button("Delete", role: .destructive) { store.remove(product); dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(product == nil ? "Add" : "Save") {
                    store.upsert(Product(id: product?.id ?? UUID().uuidString, name, product?.emoji ?? "", category, price, stock: Int(stock)))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || MON.parse(price) == nil)
            }
            .padding(.top, 8)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            if let p = product { name = p.name; category = p.category; price = MON.format(p.price, maxFraction: 18); stock = p.stock.map(String.init) ?? "" }
        }
    }
}

// MARK: - Settings

struct POSSettingsView: View {
    @EnvironmentObject var store: POSStore
    @State private var payoutDraft = ""
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                block("Business") {
                    row("Name") { TextField("", text: $store.merchantName).textFieldStyle(.plain).font(T.sans(13)).frame(width: 320) }
                }
                block("Tax") {
                    row("Rate %") {
                        TextField("0", value: $store.taxPercent, format: .number).textFieldStyle(.plain).font(T.mono(13)).frame(width: 80)
                    }
                    Text("Added on top of the discounted subtotal at checkout.").font(T.sans(12)).foregroundStyle(T.faint)
                }
                block("Payouts") {
                    row("Address") {
                        TextField("0x…", text: $payoutDraft).textFieldStyle(.plain).font(T.mono(12.5)).frame(width: 380).onSubmit(save)
                        Button("Save", action: save).buttonStyle(QuietAction()).disabled(!isAddress(payoutDraft) || payoutDraft == store.payout)
                    }
                    Text("Payments settle directly to this address.").font(T.sans(12)).foregroundStyle(T.faint)
                }
                block("Network") {
                    KV(k: "Chain", v: "\(Chain.name) (\(Chain.chainId))")
                    KV(k: "Contract", v: Chain.monadPay)
                    KV(k: "Feed", v: "monadNewHeads, monadLogs")
                    KV(k: "Tap", v: "BLE ≥ \(TapLink.tapRSSI) dBm, Bonjour")
                }
                block("Data") {
                    Button("Clear order history…") { confirmReset = true }.buttonStyle(QuietAction())
                    Text("Local history only. On-chain payments are unaffected.").font(T.sans(12)).foregroundStyle(T.faint)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 28)
            .frame(maxWidth: 720, alignment: .leading)
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

    private func block<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { Label2(title); c() }
    }
    private func row<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label).font(T.sans(13)).foregroundStyle(T.dim).frame(width: 80, alignment: .leading)
            c()
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rule() }
    }
}
