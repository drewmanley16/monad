import SwiftUI

// MARK: - Orders (list + receipt inspector)

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
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Orders", subtitle: "\(store.sales.count) payments · settled on Monad")
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(T.faint)
                        TextField("Items, wallet, tx hash", text: $query).textFieldStyle(.plain).frame(width: 190)
                    }
                    .font(.system(size: 13)).padding(.horizontal, 12).frame(height: 34)
                    .background(T.panel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.stroke))
                }

                HStack {
                    Text("ORDER").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CUSTOMER").frame(width: 130, alignment: .leading)
                    Text("STATUS").frame(width: 100, alignment: .leading)
                    Text("FINALITY").frame(width: 80, alignment: .trailing)
                    Text("AMOUNT").frame(width: 110, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(T.faint)
                .padding(.horizontal, 14)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        if filtered.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "receipt").font(.system(size: 30)).foregroundStyle(T.fire)
                                Text("No orders yet").font(.system(size: 15, weight: .semibold))
                                Text("Charges paid from Tapnad Wallet land here instantly.").font(.system(size: 12.5)).foregroundStyle(T.dim)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 80)
                        }
                        ForEach(filtered) { s in
                            Button { selected = s.id } label: { OrderRow(sale: s, selected: selected == s.id) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 28).padding(.top, 40)

            Group {
                if let s = store.sales.first(where: { $0.id == selected }) ?? store.sales.first {
                    ReceiptInspector(sale: s).id(s.id).transition(.opacity)
                } else {
                    VStack { Spacer(); Text("Select an order").foregroundStyle(T.faint); Spacer() }.frame(maxWidth: .infinity)
                }
            }
            .frame(width: 380)
            .background(T.panel.opacity(0.55))
            .overlay(alignment: .leading) { Rectangle().fill(T.stroke).frame(width: 1) }
        }
        .animation(.snappy, value: selected)
    }
}

struct OrderRow: View {
    let sale: Sale
    let selected: Bool
    @State private var hover = false

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Text(sale.lines?.first?.emoji ?? "💸").font(.system(size: 18))
                    .frame(width: 36, height: 36).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sale.event.memo.isEmpty ? "Payment" : sale.event.memo).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text(sale.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11.5)).foregroundStyle(T.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                AddressAvatar(seed: sale.event.payer, size: 20)
                Text(shortAddress(sale.event.payer)).font(.system(size: 12, design: .monospaced)).foregroundStyle(T.dim)
            }
            .frame(width: 130, alignment: .leading)
            StatePill(state: sale.latestState).frame(width: 100, alignment: .leading)
            Text(sale.finalizedMs.map { "\($0)ms" } ?? "—").font(.system(size: 12, design: .monospaced)).foregroundStyle(T.dim)
                .frame(width: 80, alignment: .trailing)
            Text("\(MON.format(sale.event.amount, maxFraction: 4)) MON").font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.white.opacity(0.07) : hover ? Color.white.opacity(0.035) : .clear)
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? AnyShapeStyle(T.fire.opacity(0.6)) : AnyShapeStyle(Color.clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct ReceiptInspector: View {
    let sale: Sale
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Tag(text: "PAID", color: T.mint)
                        StatePill(state: sale.latestState)
                        Spacer()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(MON.format(sale.event.amount, maxFraction: 5)).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("MON").font(.system(size: 15, weight: .bold)).foregroundStyle(T.dim)
                    }
                    Text(sale.date.formatted(date: .complete, time: .standard)).font(.system(size: 12)).foregroundStyle(T.faint)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("RECEIPT").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(T.faint)
                    if let lines = sale.lines, !lines.isEmpty {
                        ForEach(lines, id: \.self) { l in
                            HStack {
                                Text(l.emoji)
                                Text(l.qty > 1 ? "\(l.qty)× \(l.name)" : l.name).font(.system(size: 13))
                                Spacer()
                                Text(MON.format(l.unit * Wei(l.qty), maxFraction: 5)).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(T.dim)
                            }
                        }
                    } else {
                        Text(sale.event.memo.isEmpty ? "Payment" : sale.event.memo).font(.system(size: 13))
                    }
                    if sale.tip > 0 {
                        HStack { Text("💜"); Text("Tip").font(.system(size: 13)); Spacer()
                            Text(MON.format(sale.tip, maxFraction: 5)).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(T.dim) }
                    }
                    Rectangle().fill(T.stroke).frame(height: 1)
                    HStack {
                        Text("Total").font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Text("\(MON.format(sale.event.amount, maxFraction: 5)) MON").font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    }
                }
                .panel(radius: 14, padding: 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("CUSTOMER").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(T.faint)
                    HStack(spacing: 10) {
                        AddressAvatar(seed: sale.event.payer, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortAddress(sale.event.payer)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Text("Tapnad Wallet").font(.system(size: 11.5)).foregroundStyle(T.dim)
                        }
                        Spacer()
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sale.event.payer, forType: .string) } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(GhostButton())
                    }
                }
                .panel(radius: 14, padding: 16)

                VStack(alignment: .leading, spacing: 14) {
                    Text("SETTLEMENT").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(T.faint)
                    CommitTimeline(rows: CommitState.timeline.map { s in
                        .init(id: s.rawValue, title: s.rawValue, subtitle: s.blurb, ms: sale.states[s.rawValue].map { Int($0 * 1000) })
                    })
                    Rectangle().fill(T.stroke).frame(height: 1)
                    kv("Block", "#\(sale.event.blockNumber.formatted())")
                    kv("Invoice", shortAddress(sale.event.invoiceId))
                    Link(destination: URL(string: Chain.explorerTx + sale.event.txHash)!) {
                        HStack { Text("View transaction"); Spacer(); Text(shortAddress(sale.event.txHash)).font(.system(size: 12, design: .monospaced)); Image(systemName: "arrow.up.right") }
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(T.violet)
                }
                .panel(radius: 14, padding: 16)
            }
            .padding(20).padding(.top, 24)
        }
        .scrollIndicators(.never)
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(T.dim); Spacer(); Text(v).font(.system(size: 12.5, design: .monospaced)) }.font(.system(size: 13))
    }
}

// MARK: - Customers

struct CustomersView: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "Customers", subtitle: "Every wallet that's paid you — no sign-up, no card on file.")
                let customers = store.customers
                HStack(spacing: 12) {
                    StatTile(title: "Customers", value: "\(customers.count)", icon: "person.2.fill", color: T.violet)
                    StatTile(title: "Returning", value: "\(customers.filter { $0.visits > 1 }.count)", icon: "arrow.triangle.2.circlepath", color: T.magenta)
                    StatTile(title: "VIPs", value: "\(customers.filter { $0.tier.name == "VIP" }.count)", icon: "crown.fill", color: T.flame)
                    StatTile(title: "Avg. spend", value: customers.isEmpty ? "—" : MON.format(store.grossVolume / Wei(customers.count), maxFraction: 3), icon: "chart.bar.fill", color: T.mint)
                }
                if customers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 32)).foregroundStyle(T.fire)
                        Text("No customers yet").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(Array(customers.enumerated()), id: \.element.id) { i, c in CustomerCard(customer: c, rank: i + 1) }
                }
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
        .scrollIndicators(.never)
    }
}

struct CustomerCard: View {
    let customer: Customer
    let rank: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AddressAvatar(seed: customer.address, size: 44)
                    .overlay(alignment: .topLeading) {
                        if rank <= 3 {
                            Text("\(rank)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.black)
                                .frame(width: 18, height: 18).background(T.flame, in: Circle()).offset(x: -6, y: -6)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(shortAddress(customer.address)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    Text("Last seen \(customer.lastSeen.formatted(.relative(presentation: .named)))").font(.system(size: 11.5)).foregroundStyle(T.faint)
                }
                Spacer()
                Tag(text: customer.tier.name.uppercased(), color: customer.tier.color)
            }
            HStack {
                metric("Spent", "\(MON.format(customer.total, maxFraction: 3))")
                Spacer()
                metric("Visits", "\(customer.visits)")
                Spacer()
                metric("Favorite", customer.favorite ?? "—")
            }
        }
        .panel(radius: 16, padding: 16, glow: customer.tier.name == "VIP" ? T.flame : nil)
    }

    private func metric(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(1).foregroundStyle(T.faint)
            Text(v).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var spark: [Double]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                    .frame(width: 28, height: 28).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                if let spark, spark.count > 1 { Sparkline(values: spark, color: color).frame(width: 70, height: 24) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(.system(size: 12)).foregroundStyle(T.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: 16, padding: 16)
    }
}
