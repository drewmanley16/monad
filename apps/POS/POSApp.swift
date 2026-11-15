import SwiftUI
import CoreImage.CIFilterBuiltins

@main
struct POSApp: App {
    @StateObject private var store = POSStore()

    var body: some Scene {
        WindowGroup("Tapnad POS") {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(T.blue)
                .frame(minWidth: 1100, minHeight: 720)
                .onOpenURL { store.handle(url: $0) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)

        WindowGroup("Customer Display", id: "customer") {
            CustomerDisplay()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 640)
    }
}

enum NavSection: String, CaseIterable, Identifiable {
    case register = "Checkout", kitchen = "Orders", orders = "Transactions", customers = "Customers", reports = "Reports", items = "Items", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .register: "cart"
        case .kitchen: "list.clipboard"
        case .orders: "list.bullet.rectangle"
        case .customers: "person.2"
        case .reports: "chart.bar"
        case .items: "square.grid.2x2"
        case .settings: "gearshape"
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
            VStack(spacing: 0) {
                TopBar(section: $section)
                Rule()
                Group {
                    switch section {
                    case .register: RegisterView()
                    case .kitchen: KitchenView()
                    case .orders: OrdersView()
                    case .customers: CustomersView()
                    case .reports: InsightsView()
                    case .items: CatalogView()
                    case .settings: POSSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(T.surface)
            }
            if store.charge != .idle {
                ChargeScreen().transition(.move(edge: .bottom)).zIndex(10)
            }
        }
        .foregroundStyle(T.text)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: store.charge)
        .ignoresSafeArea()
    }
}

struct TopBar: View {
    @EnvironmentObject var store: POSStore
    @Environment(\.openWindow) private var openWindow
    @Binding var section: NavSection
    @State private var showHow = false

    var body: some View {
        HStack(spacing: 4) {
            Text("Tapnad").font(T.sans(16, .bold)).padding(.trailing, 18)
            ForEach(NavSection.allCases) { s in
                Button { section = s } label: {
                    HStack(spacing: 5) {
                    Text(s.rawValue)
                        .font(T.sans(14, section == s ? .semibold : .regular))
                        .foregroundStyle(section == s ? T.text : T.dim)
                    if s == .kitchen, store.tickets.contains(where: { $0.status == .new }) {
                        Text("\(store.tickets.filter { $0.status == .new }.count)").font(T.mono(11, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(height: 18).background(T.text, in: Capsule())
                    }
                    }
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(section == s ? Color.black.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(s.shortcut, modifiers: .command)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(store.connected ? T.green : T.amber).frame(width: 7, height: 7)
                Text(store.connected ? "Online" : "Connecting").font(T.sans(13)).foregroundStyle(T.dim)
                Text("· Block \(store.blockNumber.formatted())").font(T.mono(13)).foregroundStyle(T.dim)
                    .contentTransition(.numericText(value: Double(store.blockNumber)))
            }
            .animation(.default, value: store.blockNumber)
            Button { openWindow(id: "customer") } label: { Image(systemName: "display").frame(width: 30, height: 30) }
                .buttonStyle(.plain).help("Open customer display")
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
                .padding(.leading, 12)
            Button { showHow = true } label: { Image(systemName: "questionmark").frame(width: 30, height: 30) }
                .buttonStyle(.plain).help("How Tapnad works")
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
            Text(store.merchantName).font(T.sans(13, .medium))
                .padding(.horizontal, 10).frame(height: 30)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
        }
        .sheet(isPresented: $showHow) { HowItWorks() }
        .padding(.leading, 84).padding(.trailing, 20)
        .frame(height: 52)
        .background(T.surface)
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
