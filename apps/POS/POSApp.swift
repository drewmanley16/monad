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
                .tint(T.text)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
    }
}

enum NavSection: String, CaseIterable, Identifiable {
    case register = "Register", orders = "Orders", customers = "Customers", reports = "Reports", items = "Items", settings = "Settings"
    var id: String { rawValue }
    var shortcut: KeyEquivalent { KeyEquivalent(Character("\(NavSection.allCases.firstIndex(of: self)! + 1)")) }
}

struct RootView: View {
    @EnvironmentObject var store: POSStore
    @State private var section: NavSection = .register

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar(section: $section)
                Rule()
                Group {
                    switch section {
                    case .register: RegisterView()
                    case .orders: OrdersView()
                    case .customers: CustomersView()
                    case .reports: InsightsView()
                    case .items: CatalogView()
                    case .settings: POSSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if store.charge != .idle {
                ChargeScreen().transition(.opacity).zIndex(10)
            }
        }
        .foregroundStyle(T.text)
        .animation(.easeOut(duration: 0.2), value: store.charge)
        .ignoresSafeArea()
    }
}

struct TopBar: View {
    @EnvironmentObject var store: POSStore
    @Binding var section: NavSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("tapnad").font(T.sans(14, .semibold))
                Text("pos").font(T.sans(14)).foregroundStyle(T.faint)
                Text("·").foregroundStyle(T.faint)
                Text(store.merchantName).font(T.sans(13)).foregroundStyle(T.dim)
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(store.connected ? T.green : T.amber).frame(width: 5, height: 5)
                    Text(store.connected ? "live" : "connecting").font(T.sans(12)).foregroundStyle(T.dim)
                    Text(store.blockNumber == 0 ? "—" : store.blockNumber.formatted())
                        .font(T.mono(12)).foregroundStyle(T.text)
                        .contentTransition(.numericText(value: Double(store.blockNumber)))
                    Text(store.blockTimeMs.map { "\($0)ms" } ?? "").font(T.mono(12)).foregroundStyle(T.faint)
                }
                .animation(.default, value: store.blockNumber)
            }
            HStack(spacing: 22) {
                ForEach(NavSection.allCases) { s in
                    Button { section = s } label: {
                        VStack(spacing: 9) {
                            Text(s.rawValue).font(T.sans(13, section == s ? .medium : .regular))
                                .foregroundStyle(section == s ? T.text : T.dim)
                            Rectangle().fill(section == s ? T.text : .clear).frame(height: 1)
                        }
                        .fixedSize()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(s.shortcut, modifiers: .command)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
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
