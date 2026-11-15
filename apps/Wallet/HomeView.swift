import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: WalletStore
    @Binding var showTap: Bool
    @State private var showReceive = false
    @State private var showSettings = false
    @State private var showAddCard = false
    @State private var editing: CardAccount?
    @State private var page: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    carousel

                    HStack(spacing: 12) {
                        Button { Haptics.tap(); showTap = true } label: {
                            Label("Tap to Pay", systemImage: "wave.3.right")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 52)
                        }
                        .buttonStyle(PrimaryButton())

                        Button { showReceive = true } label: {
                            Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 52, height: 52)
                        }
                        .buttonStyle(SecondaryButton())
                        .accessibilityLabel("Add MON")
                    }
                    .padding(.horizontal, 20)

                    monthSummary.padding(.horizontal, 20)

                    recent.padding(.horizontal, 20)
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAddCard = true } label: { Label("Add Card", systemImage: "plus.rectangle.on.rectangle") }
                        if let c = store.selectedCard {
                            Button { editing = c } label: { Label("Edit \(c.name)", systemImage: "paintpalette") }
                        }
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.semibold))
                    }
                    .tint(.primary)
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showReceive) { ReceiveView().environmentObject(store).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .sheet(isPresented: $showAddCard) { CardEditor(card: nil).environmentObject(store) }
            .sheet(item: $editing) { c in CardEditor(card: c).environmentObject(store) }
            .navigationDestination(for: PaymentRecord.self) { TransactionDetailView(record: $0) }
            .onAppear { page = store.selectedCardId }
        }
    }

    // MARK: Card carousel

    private var carousel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(store.cards) { card in
                        WalletCard(card: card, balance: store.balances[card.id])
                            .containerRelativeFrame(.horizontal) { w, _ in w - 40 }
                            .scrollTransition(axis: .horizontal) { v, phase in
                                v.scaleEffect(phase.isIdentity ? 1 : 0.92).opacity(phase.isIdentity ? 1 : 0.6)
                            }
                            .onTapGesture { showReceive = true }
                            .contextMenu {
                                Button { editing = card } label: { Label("Edit Card", systemImage: "paintpalette") }
                                Button { UIPasteboard.general.string = card.address } label: { Label("Copy Address", systemImage: "doc.on.doc") }
                            }
                            .id(card.id)
                    }
                    AddCardTile { showAddCard = true }
                        .containerRelativeFrame(.horizontal) { w, _ in w - 40 }
                        .scrollTransition(axis: .horizontal) { v, phase in v.scaleEffect(phase.isIdentity ? 1 : 0.92) }
                        .id(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            .onChange(of: page) { _, new in
                if let new, store.cards.contains(where: { $0.id == new }) { store.selectedCardId = new; Haptics.soft() }
            }

            HStack(spacing: 6) {
                ForEach(store.cards) { c in
                    Capsule().fill(c.id == store.selectedCardId ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: c.id == store.selectedCardId ? 16 : 6, height: 6)
                }
            }
            .animation(.snappy, value: store.selectedCardId)
        }
    }

    // MARK: Month summary

    private var monthSummary: some View {
        let recs = store.records()
        let spent = store.spend(recs)
        let byCat = Dictionary(grouping: recs, by: \.resolvedCategory).mapValues { store.spend($0) }
        return NavigationLink { InsightsView(embedded: true) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Spent in \(Date.now.formatted(.dateTime.month(.wide)))").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.3f", spent)).font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("MON").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(recs.count) payments").font(.footnote).foregroundStyle(.secondary)
                }
                // stacked category bar
                GeometryReader { g in
                    HStack(spacing: 2) {
                        if spent == 0 {
                            Capsule().fill(Color.secondary.opacity(0.15))
                        } else {
                            ForEach(ExpenseCategory.allCases.filter { (byCat[$0] ?? 0) > 0 }) { c in
                                Rectangle().fill(c.color.opacity(0.75))
                                    .frame(width: max(4, g.size.width * (byCat[c] ?? 0) / spent - 2))
                            }
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
            }
            .surface()
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Transactions").font(.title3.weight(.semibold))
                Spacer()
            }
            let recs = store.history.filter { $0.cardId == store.selectedCardId }.prefix(5)
            if recs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wave.3.right.circle").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("No payments on this card").font(.subheadline.weight(.medium))
                    Text("Tap your phone on a Tapnad register to pay.").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .surface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recs.enumerated()), id: \.element.id) { i, rec in
                        NavigationLink(value: rec) { ActivityRow(rec: rec) }.buttonStyle(.plain)
                        if i < recs.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
                .surface(padding: 0)
            }
        }
    }
}

// MARK: - Rows

struct ActivityRow: View {
    let rec: PaymentRecord
    var body: some View {
        HStack(spacing: 12) {
            AddressAvatar(seed: rec.merchant ?? rec.merchantName, label: rec.merchantName, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.merchantName).font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Text(rec.date.formatted(.relative(presentation: .named)))
                    Text("·")
                    Text(rec.resolvedCategory.name)
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("\((rec.incoming ?? false) ? "+" : "−")\(MON.format(rec.amount)) MON").font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle((rec.incoming ?? false) ? Color.green : .primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Card

struct WalletCard: View {
    let card: CardAccount
    let balance: Wei?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.name).font(.system(size: 15, weight: .semibold))
                if card.isBusiness { Text("Business").font(.system(size: 12)).opacity(0.65) }
                Spacer()
                Image(systemName: "wave.3.right").font(.system(size: 15, weight: .medium)).opacity(0.75)
            }
            Spacer()
            if !compact {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(balance.map { MON.format($0, maxFraction: 3) } ?? "—")
                        .font(.system(size: 32, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("MON").font(.system(size: 14, weight: .medium)).opacity(0.65)
                }
                .padding(.bottom, 8)
            }
            HStack {
                Text(shortAddress(card.address)).font(.system(size: 12, design: .monospaced)).opacity(0.65)
                Spacer()
                Text("tapnad").font(.system(size: 12, weight: .semibold)).opacity(0.65)
            }
        }
        .foregroundStyle(card.theme.foreground)
        .padding(20)
        .aspectRatio(1.586, contentMode: .fit)
        .background(card.theme.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

struct AddCardTile: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 26, weight: .semibold))
                Text("Add Card").font(.headline)
                Text("Separate personal & business spend").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(.secondary.opacity(0.5)))
            .aspectRatio(1.586, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card editor

struct CardEditor: View {
    @EnvironmentObject var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    let card: CardAccount?
    @State private var name = ""
    @State private var theme: CardTheme = .aurora
    @State private var business = false
    @State private var importKey = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WalletCard(card: CardAccount(id: card?.id ?? UUID(), name: name.isEmpty ? "New Card" : name, theme: theme,
                                                 isBusiness: business, address: card?.address ?? "0x0000…0000"),
                               balance: card.flatMap { store.balances[$0.id] })
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        .animation(.snappy, value: theme)
                }
                Section("Details") {
                    TextField("Card name", text: $name)
                    Toggle("Business card", isOn: $business)
                }
                Section("Theme") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CardTheme.allCases) { t in
                            Circle().fill(t.gradient).frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: theme == t ? 2.5 : 0).padding(-4))
                                .onTapGesture { theme = t; Haptics.soft() }
                        }
                    }
                    .padding(.vertical, 6)
                }
                if card == nil {
                    Section {
                        SecureField("Optional: import 0x… private key", text: $importKey)
                    } footer: { Text("Leave empty to create a fresh wallet for this card.") }
                } else {
                    Section {
                        Button("Delete Card", role: .destructive) { confirmDelete = true }
                            .disabled(store.cards.count < 2)
                    } footer: { Text("Deleting removes the key from this device. Move funds first.") }
                }
            }
            .navigationTitle(card == nil ? "Add Card" : "Edit Card").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(card == nil ? "Add" : "Save", action: save).fontWeight(.semibold) }
            }
            .confirmationDialog("Delete this card?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let card { store.delete(card) }; dismiss() }
            }
            .onAppear {
                if let card { name = card.name; theme = card.theme; business = card.isBusiness }
                else { theme = CardTheme.allCases.first { t in !store.cards.contains { $0.theme == t } } ?? .aurora }
            }
        }
    }

    private func save() {
        let n = name.isEmpty ? (business ? "Business" : "Card \(store.cards.count + 1)") : name
        if var c = card {
            c.name = n; c.theme = theme; c.isBusiness = business
            store.update(c)
        } else if !importKey.isEmpty {
            guard store.importCard(hex: importKey, name: n, theme: theme, business: business) else { return }
        } else if let c = store.createCard(name: n, theme: theme, business: business) {
            store.selectedCardId = c.id
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Buttons

struct PrimaryButton: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(scheme == .dark ? .black : .white)
            .background(scheme == .dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
