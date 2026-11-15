import SwiftUI

struct TapToPayView: View {
    @EnvironmentObject var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = ReaderScanner()
    var preloaded: PaymentRequest?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if let card = store.selectedCard {
                    WalletCard(card: card, balance: store.balance, compact: true)
                        .id(card.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        .frame(maxWidth: store.phase == .scanning ? 300 : 200)
                        .padding(.top, 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.phase)
                }

                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .onAppear(perform: start)
        .onDisappear { scanner.stop() }
    }

    private var isFailed: Bool { if case .failed = store.phase { return true }; return false }

    private func start() {
        store.beginTap()
        if let preloaded { store.found(preloaded); return }
        scanner.start(payer: store.address) { req in store.found(req) }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .tint(.primary)
            .opacity(store.phase == .sending || store.phase == .authorizing ? 0 : 1)
            Spacer()
        }
        .frame(height: 44)
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .scanning: scanning.transition(.opacity)
        case .confirm, .authorizing, .failed: confirm.transition(.move(edge: .bottom).combined(with: .opacity))
        case .sending: processing.transition(.opacity)
        case .approved: approved.transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    // MARK: Scanning

    private var scanning: some View {
        VStack(spacing: 22) {
            ContactlessRings(size: 230)
            VStack(spacing: 6) {
                Text(scanner.readerName.map { "Found \($0)" } ?? "Hold Near Reader")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)
                Text(ReaderScanner.isSimulator
                     ? "Looking for a Tapnad register on this network…"
                     : "Hold the top of your iPhone against the Mac running Tapnad POS.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if !ReaderScanner.isSimulator {
                ProximityMeter(value: scanner.proximity).frame(width: 180)
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: Confirm

    private var confirm: some View {
        VStack(spacing: 20) {
            if let req = store.request {
                VStack(spacing: 6) {
                    AddressAvatar(seed: req.merchant, label: req.merchantName, size: 48)
                    Text(req.merchantName).font(.headline).padding(.top, 6)
                    if !req.memo.isEmpty {
                        Text(req.memo).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(MON.format(store.payAmount, maxFraction: 6)).font(.system(size: 56, weight: .semibold, design: .rounded))
                    Text("MON").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                .minimumScaleFactor(0.5).lineLimit(1)

                Picker("Tip", selection: $store.tipPercent) {
                    Text("No tip").tag(0); Text("10%").tag(10); Text("15%").tag(15); Text("20%").tag(20)
                }
                .pickerStyle(.segmented)
                .disabled(store.phase != .confirm && !isFailed)

                VStack(spacing: 0) {
                    cardPicker
                    Divider()
                    detailRow("To", shortAddress(req.merchant), mono: true)
                    Divider()
                    detailRow("Network", Chain.name)
                }
                .surface(padding: 0)

                if case .failed(let msg) = store.phase {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.leading)
                }
                if store.insufficient {
                    Label("Not enough MON. Add funds to continue.", systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }

                Button { Task { await store.pay() } } label: {
                    HStack(spacing: 8) {
                        if store.phase == .authorizing { ProgressView().tint(.white) }
                        else { Image(systemName: Biometrics.icon) }
                        Text(isFailed ? "Try Again" : "Pay with Face ID")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(PrimaryButton())
                .disabled(store.phase == .authorizing || store.insufficient)
            }
        }
        .padding(.bottom, 16)
    }

    private var cardPicker: some View {
        HStack {
            Text("Pay with").foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(store.cards) { c in
                    Button {
                        withAnimation(.snappy) { store.selectedCardId = c.id }; Haptics.soft()
                    } label: {
                        Text("\(c.name) · \(store.balances[c.id].map { MON.format($0, maxFraction: 2) } ?? "—") MON")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let c = store.selectedCard {
                        RoundedRectangle(cornerRadius: 3).fill(c.theme.gradient).frame(width: 22, height: 14)
                        Text("\(c.name) · \(store.balance.map { MON.format($0, maxFraction: 2) } ?? "—") MON").foregroundStyle(.primary)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .disabled(store.phase != .confirm && !isFailed)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func detailRow(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(mono ? .system(.subheadline, design: .monospaced) : .subheadline.weight(.medium))
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    // MARK: Processing / approved

    private var processing: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Processing").font(.title3.weight(.semibold))
            Text("Broadcasting to Monad…").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.bottom, 60)
    }

    private var approved: some View {
        VStack(spacing: 22) {
            SuccessCheck(size: 88)
            if let req = store.request {
                VStack(spacing: 4) {
                    Text("Paid \(MON.format(store.payAmount, maxFraction: 6)) MON").font(.title2.weight(.semibold))
                    Text(req.merchantName).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            CommitTimeline(rows:
                [.init(id: "signed", title: "Signed on iPhone", subtitle: "Key stays on device · Face ID", ms: store.signedMs)] +
                CommitState.timeline.map { .init(id: $0.rawValue, title: $0.rawValue, subtitle: $0.blurb, ms: store.stateMs[$0]) }
            )
            .surface()

            if let h = store.txHash {
                Link(destination: URL(string: Chain.explorerTx + h)!) {
                    Label("View on Explorer", systemImage: "arrow.up.right").font(.footnote.weight(.medium))
                }
            }

            Button { dismiss() } label: {
                Text("Done").font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 54)
            }
            .buttonStyle(PrimaryButton())
        }
        .padding(.bottom, 16)
    }
}

struct ProximityMeter: View {
    let value: Double
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.primary).frame(width: max(6, g.size.width * value))
                }
            }
            .frame(height: 6)
            Text(value > 0.85 ? "Almost there…" : value > 0.2 ? "Move closer" : "Searching")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
