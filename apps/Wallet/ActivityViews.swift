import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var store: WalletStore
    @State private var query = ""
    @State private var cardFilter: UUID?
    @State private var categoryFilter: ExpenseCategory?

    private var filtered: [PaymentRecord] {
        store.history.filter { r in
            (cardFilter == nil || r.cardId == cardFilter) &&
            (categoryFilter == nil || r.resolvedCategory == categoryFilter) &&
            (query.isEmpty || r.merchantName.localizedCaseInsensitiveContains(query) ||
             r.memo.localizedCaseInsensitiveContains(query) || (r.note ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    private var grouped: [(day: Date, recs: [PaymentRecord])] {
        let cal = Calendar.current
        return Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("All cards", nil, selected: cardFilter == nil) { cardFilter = nil }
                            ForEach(store.cards) { c in
                                chip(c.name, c.theme.gradient, selected: cardFilter == c.id) { cardFilter = cardFilter == c.id ? nil : c.id }
                            }
                            Divider().frame(height: 20)
                            ForEach(ExpenseCategory.allCases) { cat in
                                chip(cat.name, nil, icon: cat.icon, tint: cat.color, selected: categoryFilter == cat) {
                                    categoryFilter = categoryFilter == cat ? nil : cat
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                if grouped.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No Transactions" : "No Results",
                                           systemImage: "list.bullet.rectangle",
                                           description: Text(query.isEmpty ? "Payments you make show up here." : "Try a different search."))
                        .listRowBackground(Color.clear)
                }

                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.recs) { rec in
                            NavigationLink(value: rec) { ActivityRow(rec: rec).padding(.horizontal, -14) }
                        }
                    } header: {
                        HStack {
                            Text(group.day.formatted(.relative(presentation: .named, unitsStyle: .wide)).capitalizedFirst == "Now"
                                 ? "Today" : dayLabel(group.day))
                            Spacer()
                            Text(store.spend(group.recs).formatted(.currency(code: "USD"))).monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Merchants, items, notes")
            .navigationTitle("Activity")
            .navigationDestination(for: PaymentRecord.self) { TransactionDetailView(record: $0) }
            .animation(.snappy, value: filtered.map(\.id))
        }
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func chip(_ title: String, _ swatch: LinearGradient?, icon: String? = nil, tint: Color = .primary,
                      selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.soft() }) {
            HStack(spacing: 6) {
                if let swatch { RoundedRectangle(cornerRadius: 3).fill(swatch).frame(width: 16, height: 11) }
                if let icon { Image(systemName: icon).foregroundStyle(selected ? .white : tint) }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(selected ? Color(.systemBackground) : .primary)
            .background(selected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transaction detail (receipt)

struct TransactionDetailView: View {
    @EnvironmentObject var store: WalletStore
    let record: PaymentRecord
    @State private var note = ""
    @State private var copied = false

    private var rec: PaymentRecord { store.history.first { $0.id == record.id } ?? record }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    AddressAvatar(seed: rec.merchant ?? rec.merchantName, label: rec.merchantName, size: 64)
                    Text(rec.merchantName).font(.title3.weight(.semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(((rec.incoming ?? false) ? "+" : "−") + Money.usd(rec.amount)).font(.system(size: 44, weight: .semibold, design: .rounded))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: rec.finalizedMs != nil ? "checkmark.seal.fill" : "clock.fill")
                        Text(rec.finalizedMs != nil ? "Finalized" : "Completed")
                        Text("·").foregroundStyle(.secondary)
                        Text(rec.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(rec.finalizedMs != nil ? Brand.success : .secondary)
                }
                .padding(.top, 8)

                // Receipt
                VStack(alignment: .leading, spacing: 0) {
                    Text("RECEIPT").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                    ForEach(Array(rec.items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text("\(item.qty)×").foregroundStyle(.secondary).monospacedDigit().frame(width: 28, alignment: .leading)
                            Text(item.name)
                            Spacer()
                        }
                        .font(.subheadline).padding(.horizontal, 16).padding(.vertical, 6)
                    }
                    if rec.items.isEmpty {
                        Text("Payment").font(.subheadline).padding(.horizontal, 16).padding(.vertical, 6)
                    }
                    DashedDivider().padding(.vertical, 8).padding(.horizontal, 16)
                    row("Subtotal", "\(Money.usd(rec.amount))")
                    row("Network fee", rec.fee > 0 ? "\(Money.usd(rec.fee))" : "—")
                    row("Total", "\(Money.usd(rec.amount + rec.fee))", bold: true).padding(.bottom, 8)
                }
                .surface(padding: 0)

                // Expense
                VStack(spacing: 0) {
                    HStack {
                        Text("Category").foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(ExpenseCategory.allCases) { c in
                                Button { store.setCategory(c, for: rec); Haptics.soft() } label: { Label(c.name, systemImage: c.icon) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: rec.resolvedCategory.icon).foregroundStyle(rec.resolvedCategory.color)
                                Text(rec.resolvedCategory.name).foregroundStyle(.primary)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    Divider().padding(.leading, 16)
                    if let card = store.card(for: rec) {
                        HStack {
                            Text("Card").foregroundStyle(.secondary)
                            Spacer()
                            RoundedRectangle(cornerRadius: 3).fill(card.theme.gradient).frame(width: 22, height: 14)
                            Text(card.name)
                            if card.isBusiness {
                                Text("Business").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15), in: Capsule()).foregroundStyle(.blue)
                            }
                        }
                        .padding(16)
                        Divider().padding(.leading, 16)
                    }
                    TextField("Add a note (e.g. client lunch)", text: $note, axis: .vertical)
                        .padding(16)
                        .onSubmit { store.setNote(note, for: rec) }
                }
                .font(.subheadline)
                .surface(padding: 0)

                // Settlement
                VStack(alignment: .leading, spacing: 14) {
                    Text("Settlement on Monad").font(.subheadline.weight(.semibold))
                    CommitTimeline(rows: [
                        .init(id: "s", title: "Broadcast", subtitle: "Signed on this iPhone", ms: 0),
                        .init(id: "p", title: "Proposed", subtitle: CommitState.proposed.blurb, ms: rec.proposedMs),
                        .init(id: "v", title: "Voted", subtitle: CommitState.voted.blurb, ms: rec.votedMs),
                        .init(id: "f", title: "Finalized", subtitle: CommitState.finalized.blurb, ms: rec.finalizedMs),
                    ])
                    Divider()
                    Button {
                        UIPasteboard.general.string = rec.txHash; copied = true; Haptics.tap()
                    } label: {
                        HStack {
                            Text("Transaction").foregroundStyle(.secondary)
                            Spacer()
                            Text(shortAddress(rec.txHash)).font(.system(.subheadline, design: .monospaced))
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    Link(destination: URL(string: Chain.explorerTx + rec.txHash)!) {
                        HStack { Text("View on Explorer"); Spacer(); Image(systemName: "arrow.up.right") }
                    }
                }
                .font(.subheadline)
                .surface()
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { note = rec.note ?? "" }
        .onDisappear { if note != (rec.note ?? "") { store.setNote(note, for: rec) } }
    }

    private func row(_ k: String, _ v: String, bold: Bool = false) -> some View {
        HStack {
            Text(k).foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(v).monospacedDigit()
        }
        .font(bold ? .subheadline.weight(.semibold) : .subheadline)
        .padding(.horizontal, 16).padding(.vertical, 5)
    }
}

struct DashedDivider: View {
    var body: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.secondary.opacity(0.4)).frame(height: 1)
    }
    struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: .init(x: 0, y: r.midY)); p.addLine(to: .init(x: r.width, y: r.midY)); return p }
    }
}
