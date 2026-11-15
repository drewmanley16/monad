import SwiftUI
import CoreImage.CIFilterBuiltins

@main
struct POSApp: App {
    @StateObject private var store = POSStore()

    var body: some Scene {
        WindowGroup("Tapnad POS") {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(T.violet)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
    }
}

enum NavSection: String, CaseIterable, Identifiable {
    case register = "Register", orders = "Orders", customers = "Customers", insights = "Insights", catalog = "Catalog", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .register: "square.grid.2x2.fill"
        case .orders: "receipt.fill"
        case .customers: "person.2.fill"
        case .insights: "chart.xyaxis.line"
        case .catalog: "shippingbox.fill"
        case .settings: "gearshape.fill"
        }
    }
    var shortcut: KeyEquivalent { KeyEquivalent(Character("\(NavSection.allCases.firstIndex(of: self)! + 1)")) }
}

struct RootView: View {
    @EnvironmentObject var store: POSStore
    @State private var section: NavSection = .register

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            HStack(spacing: 0) {
                Sidebar(section: $section)
                Rectangle().fill(T.stroke).frame(width: 1)
                ZStack {
                    switch section {
                    case .register: RegisterView()
                    case .orders: OrdersView()
                    case .customers: CustomersView()
                    case .insights: InsightsView()
                    case .catalog: CatalogView()
                    case .settings: POSSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .id(section)
            }

            if store.charge != .idle {
                ChargeTakeover()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
                    .zIndex(10)
            }
        }
        .foregroundStyle(T.text)
        .animation(.easeOut(duration: 0.18), value: section)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: store.charge)
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: POSStore
    @Binding var section: NavSection
    @State private var hover: NavSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(T.fireDiag).frame(width: 30, height: 30)
                        .shadow(color: T.magenta.opacity(0.6), radius: 10)
                    Image(systemName: "wave.3.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("tapnad").font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text("POINT OF SALE").font(.system(size: 8.5, weight: .bold)).tracking(1.4).foregroundStyle(T.faint)
                }
            }
            .padding(.horizontal, 18).padding(.top, 46).padding(.bottom, 26)

            VStack(spacing: 3) {
                ForEach(NavSection.allCases) { s in
                    Button { section = s } label: {
                        HStack(spacing: 11) {
                            Image(systemName: s.icon).font(.system(size: 13, weight: .semibold)).frame(width: 18)
                                .foregroundStyle(section == s ? AnyShapeStyle(T.fire) : AnyShapeStyle(T.dim))
                            Text(s.rawValue).font(.system(size: 13.5, weight: section == s ? .semibold : .medium))
                                .foregroundStyle(section == s ? T.text : T.dim)
                            Spacer()
                            if s == .orders, !store.todaySales.isEmpty {
                                Text("\(store.todaySales.count)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(T.dim)
                                    .padding(.horizontal, 6).padding(.vertical, 1).background(Color.white.opacity(0.07), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(section == s ? Color.white.opacity(0.07) : hover == s ? Color.white.opacity(0.035) : .clear)
                        )
                        .overlay(alignment: .leading) {
                            if section == s {
                                Capsule().fill(T.fire).frame(width: 3, height: 16).offset(x: -1).shadow(color: T.magenta, radius: 6)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hover = $0 ? s : nil }
                    .keyboardShortcut(s.shortcut, modifiers: .command)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            ChainWidget().padding(12)

            HStack(spacing: 10) {
                AddressAvatar(seed: store.payout, label: store.merchantName, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.merchantName).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(shortAddress(store.payout)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(T.faint)
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .frame(width: 236)
        .background(LinearGradient(colors: [T.panel.opacity(0.6), T.bg], startPoint: .top, endPoint: .bottom))
    }
}

struct ChainWidget: View {
    @EnvironmentObject var store: POSStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(store.connected ? T.mint : T.flame).frame(width: 7, height: 7)
                    .shadow(color: store.connected ? T.mint : T.flame, radius: 4)
                Text(store.connected ? "LIVE" : "CONNECTING").font(.system(size: 9.5, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(store.connected ? T.mint : T.flame)
                Spacer()
                Text("Testnet").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.faint)
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.blockNumber == 0 ? "—" : store.blockNumber.formatted())
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText(value: Double(store.blockNumber)))
                    Text("block height").font(.system(size: 9.5)).foregroundStyle(T.faint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.blockTimeMs.map { "\($0)ms" } ?? "—").font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(T.fire)
                    Text("block time").font(.system(size: 9.5)).foregroundStyle(T.faint)
                }
            }
            Sparkline(values: store.blockTimeHistory.isEmpty ? [0, 0] : store.blockTimeHistory, color: T.magenta)
                .frame(height: 26)
        }
        .panel(radius: 12, padding: 12)
        .animation(.snappy, value: store.blockNumber)
    }
}

func qrNSImage(_ s: String) -> NSImage {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(s.utf8); f.correctionLevel = "M"
    guard let out = f.outputImage?.transformed(by: .init(scaleX: 10, y: 10)) else { return NSImage() }
    let rep = NSCIImageRep(ciImage: out)
    let img = NSImage(size: rep.size); img.addRepresentation(rep)
    return img
}
