import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: WalletStore
    @Binding var deepLink: PaymentRequest?
    @State private var showTap = false
    @State private var showReceive = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    WalletCard(balance: store.balance, address: store.address)
                        .onTapGesture { showReceive = true }

                    HStack(spacing: 12) {
                        Button { Haptics.tap(); showTap = true } label: {
                            Label("Tap to Pay", systemImage: "wave.3.right")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 52)
                        }
                        .buttonStyle(PrimaryButton())

                        Button { showReceive = true } label: {
                            Label("Add", systemImage: "plus")
                                .font(.body.weight(.semibold))
                                .frame(width: 96, height: 52)
                        }
                        .buttonStyle(SecondaryButton())
                    }

                    activity
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.semibold))
                    }
                    .tint(.primary)
                }
            }
            .refreshable { await store.refresh() }
            .task {
                await store.refresh()
                // light polling so the balance feels live
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    await store.refresh()
                }
            }
            .fullScreenCover(isPresented: $showTap, onDismiss: { store.endPayment() }) {
                TapToPayView(preloaded: deepLink).environmentObject(store)
            }
            .sheet(isPresented: $showReceive) { ReceiveView().environmentObject(store).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .onChange(of: deepLink) { _, new in if new != nil { showTap = true } }
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.title3.weight(.semibold))
            if store.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wave.3.right.circle").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("No payments yet").font(.subheadline.weight(.medium))
                    Text("Tap your phone on a Tapnad register to pay.").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
                .surface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.history.prefix(20).enumerated()), id: \.element.id) { i, rec in
                        Link(destination: URL(string: Chain.explorerTx + rec.txHash)!) { ActivityRow(rec: rec) }
                            .buttonStyle(.plain)
                        if i < min(store.history.count, 20) - 1 { Divider().padding(.leading, 60) }
                    }
                }
                .surface(padding: 0)
            }
        }
    }
}

struct ActivityRow: View {
    let rec: PaymentRecord
    var body: some View {
        HStack(spacing: 12) {
            Text(String(rec.merchantName.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Brand.purple)
                .frame(width: 36, height: 36)
                .background(Brand.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.merchantName).font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Text(rec.memo.isEmpty ? rec.date.formatted(.relative(presentation: .named)) : rec.memo)
                    if let ms = rec.proposedMs {
                        Text("·")
                        Image(systemName: "bolt.fill").font(.system(size: 9))
                        Text("\(ms) ms")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("−\(MON.format(rec.amount)) MON")
                .font(.subheadline.monospacedDigit().weight(.medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Card

struct WalletCard: View {
    let balance: Wei?
    let address: String
    var compact = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.cardGradient)
                .overlay(alignment: .topTrailing) {
                    // soft light bloom
                    Circle().fill(.white.opacity(0.16)).frame(width: 260).blur(radius: 50).offset(x: 80, y: -120)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    HStack(spacing: 7) {
                        Image(systemName: "hexagon.fill").font(.system(size: 15, weight: .bold))
                        Text("tapnad").font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "wave.3.right").font(.system(size: 18, weight: .semibold)).opacity(0.9)
                }
                Spacer()
                if !compact {
                    Text("Balance").font(.footnote.weight(.medium)).opacity(0.75)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(balance.map { MON.format($0, maxFraction: 3) } ?? "—")
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("MON").font(.headline).opacity(0.8)
                    }
                    .padding(.bottom, 10)
                }
                HStack {
                    Text(shortAddress(address)).font(.system(.footnote, design: .monospaced)).opacity(0.8)
                    Spacer()
                    Text("TESTNET").font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: Brand.indigo.opacity(0.35), radius: 24, y: 14)
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
