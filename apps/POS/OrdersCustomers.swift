import SwiftUI

// MARK: - Orders

struct OrdersView: View {
    @EnvironmentObject var store: POSStore
    @State private var selected: String?
    @State private var query = ""

    private var filtered: [Sale] {
        store.sales.filter { s in
            query.isEmpty || s.event.memo.localizedCaseInsensitiveContains(query) ||
            s.event.payer.localizedCaseInsensitiveContains(query) || s.event.txHash.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(T.faint)
                    TextField("Search items, wallets, transactions", text: $query).textFieldStyle(.plain).font(T.sans(13))
                    Spacer()
                    Text("\(store.sales.count) orders").font(T.mono(12)).foregroundStyle(T.faint)
                }
                .padding(.horizontal, 28).frame(height: 44)
                Rule()

                HStack(spacing: 0) {
                    Text("Time").frame(width: 92, alignment: .leading)
                    Text("Items").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Customer").frame(width: 120, alignment: .leading)
                    Text("Status").frame(width: 100, alignment: .leading)
                    Text("Amount").frame(width: 90, alignment: .trailing)
                }
                .font(T.sans(11.5)).foregroundStyle(T.faint)
                .padding(.horizontal, 28).frame(height: 34)
                Rule()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filtered.isEmpty {
                            Text(query.isEmpty ? "No orders yet." : "No matches.").font(T.sans(13)).foregroundStyle(T.dim)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(28)
                        }
                        ForEach(filtered) { s in
                            Button { selected = s.id } label: { OrderRow(sale: s, selected: (selected ?? store.sales.first?.id) == s.id) }
                                .buttonStyle(.plain)
                            Rule().padding(.leading, 28)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            VRule()

            Group {
                if let s = store.sales.first(where: { $0.id == selected }) ?? store.sales.first {
                    ReceiptInspector(sale: s).id(s.id)
                } else {
                    Text("No order selected.").font(T.sans(13)).foregroundStyle(T.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24)
                }
            }
            .frame(width: 380)
        }
    }
}

struct OrderRow: View {
    let sale: Sale
    let selected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 0) {
            Text(sale.date.formatted(date: .omitted, time: .shortened)).font(T.mono(12.5)).foregroundStyle(T.dim)
                .frame(width: 92, alignment: .leading)
            Text(sale.event.memo.isEmpty ? "Payment" : sale.event.memo).font(T.sans(13)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shortAddress(sale.event.payer)).font(T.mono(12.5)).foregroundStyle(T.dim)
                .frame(width: 120, alignment: .leading)
            StateLabel(state: sale.latestState).frame(width: 100, alignment: .leading)
            Text(MON.format(sale.event.amount, maxFraction: 4)).font(T.mono(13)).frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 28).frame(height: 40)
        .background(selected ? Color.white.opacity(0.05) : hover ? T.hover : .clear)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(T.text).frame(width: 2) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct ReceiptInspector: View {
    let sale: Sale
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Label2("Order")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(MON.format(sale.event.amount, maxFraction: 4)).font(T.mono(34, .light))
                        Text("MON").font(T.mono(13)).foregroundStyle(T.dim)
                    }
                    Text(sale.date.formatted(date: .abbreviated, time: .standard)).font(T.mono(12)).foregroundStyle(T.faint)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Label2("Items")
                    if let lines = sale.lines, !lines.isEmpty {
                        ForEach(lines, id: \.self) { l in
                            KV(k: l.qty > 1 ? "\(l.qty)× \(l.name)" : l.name, v: MON.format(l.unit * Wei(l.qty), maxFraction: 4))
                        }
                    } else {
                        Text(sale.event.memo.isEmpty ? "Payment" : sale.event.memo).font(T.sans(13))
                    }
                    if sale.tip > 0 { KV(k: "Tip", v: MON.format(sale.tip, maxFraction: 4)) }
                    Rule()
                    KV(k: "Total", v: MON.format(sale.event.amount, maxFraction: 4), strong: true)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Label2("Settlement")
                    ForEach(CommitState.timeline, id: \.self) { s in
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Circle().fill(sale.states[s.rawValue] != nil ? s.color : T.faint.opacity(0.4)).frame(width: 5, height: 5)
                            Text(s.rawValue).font(T.sans(13)).foregroundStyle(T.dim)
                            Leader()
                            Text(sale.states[s.rawValue].map { "+\(Int($0 * 1000)) ms" } ?? "—").font(T.mono(13))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Label2("Details")
                    KV(k: "Customer", v: shortAddress(sale.event.payer))
                    KV(k: "Block", v: sale.event.blockNumber.formatted())
                    KV(k: "Invoice", v: shortAddress(sale.event.invoiceId))
                    HStack(spacing: 14) {
                        Link("View transaction ↗", destination: URL(string: Chain.explorerTx + sale.event.txHash)!)
                        Button("Copy wallet") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sale.event.payer, forType: .string)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(T.sans(12.5)).foregroundStyle(T.dim)
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - Customers

struct CustomersView: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        let customers = store.customers
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 36) {
                Metric(label: "Customers", value: "\(customers.count)")
                Metric(label: "Returning", value: "\(customers.filter { $0.visits > 1 }.count)")
                Metric(label: "Avg. spend", value: customers.isEmpty ? "—" : MON.format(store.grossVolume / Wei(customers.count), maxFraction: 3))
                Spacer()
            }
            .padding(.horizontal, 28).padding(.vertical, 22)
            Rule()

            HStack(spacing: 0) {
                Text("Wallet").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tier").frame(width: 90, alignment: .leading)
                Text("Visits").frame(width: 70, alignment: .trailing)
                Text("Usual").frame(width: 170, alignment: .leading).padding(.leading, 28)
                Text("Last seen").frame(width: 110, alignment: .leading)
                Text("Spent").frame(width: 90, alignment: .trailing)
            }
            .font(T.sans(11.5)).foregroundStyle(T.faint)
            .padding(.horizontal, 28).frame(height: 34)
            Rule()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if customers.isEmpty {
                        Text("No customers yet.").font(T.sans(13)).foregroundStyle(T.dim)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(28)
                    }
                    ForEach(customers) { c in
                        HStack(spacing: 0) {
                            Text(c.address).font(T.mono(12.5)).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 6) {
                                Circle().fill(c.tier.color).frame(width: 5, height: 5)
                                Text(c.tier.name).font(T.sans(12.5)).foregroundStyle(T.dim)
                            }
                            .frame(width: 90, alignment: .leading)
                            Text("\(c.visits)").font(T.mono(12.5)).frame(width: 70, alignment: .trailing)
                            Text(c.favorite ?? "—").font(T.sans(12.5)).foregroundStyle(T.dim).lineLimit(1)
                                .frame(width: 170, alignment: .leading).padding(.leading, 28)
                            Text(c.lastSeen.formatted(.relative(presentation: .named))).font(T.sans(12.5)).foregroundStyle(T.dim)
                                .frame(width: 110, alignment: .leading)
                            Text(MON.format(c.total, maxFraction: 3)).font(T.mono(13)).frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 28).frame(height: 40)
                        Rule().padding(.leading, 28)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

struct Metric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(T.sans(12)).foregroundStyle(T.faint)
            Text(value).font(T.mono(22, .light)).contentTransition(.numericText())
        }
    }
}
