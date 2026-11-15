import SwiftUI
import CoreImage.CIFilterBuiltins

/// Routes tapnadpos:// links to the register regardless of which window is frontmost.
final class POSAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: POSStore?
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let store else { pending += urls; return }
        Task { @MainActor in urls.forEach { store.handle(url: $0) } }
    }

    func attach(_ s: POSStore) {
        store = s
        let queued = pending; pending = []
        Task { @MainActor in queued.forEach { s.handle(url: $0) } }
    }
}

@main
struct POSApp: App {
    @NSApplicationDelegateAdaptor(POSAppDelegate.self) private var delegate
    @StateObject private var store = POSStore()

    var body: some Scene {
        WindowGroup("Tapnad POS") {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(T.blue)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear { delegate.attach(store) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .handlesExternalEvents(matching: [])     // links go to POSAppDelegate, not a new window

        WindowGroup("Customer Display", id: "customer") {
            CustomerDisplay()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 640)
        .handlesExternalEvents(matching: [])
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
            GlassBackdrop()
            VStack(spacing: 10) {
                TopBar(section: $section)
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
                .modifier(SectionPanel(isRegister: section == .register))
            }
            .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 6)
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
            Text("Tapnad").font(T.sans(16, .bold)).fixedSize()
            Text("TEST MODE").font(T.sans(10, .bold)).tracking(0.6).foregroundStyle(T.dim).fixedSize()
                .padding(.horizontal, 6).frame(height: 18).overlay(Capsule().strokeBorder(T.rule))
                .padding(.leading, 6).padding(.trailing, 14)
                .help("Payments settle in Monad testnet MON at a fixed $100/MON display rate")
            ForEach(NavSection.allCases) { s in
                Button { section = s } label: {
                    HStack(spacing: 5) {
                    Text(s.rawValue)
                        .font(T.sans(14, section == s ? .semibold : .regular)).fixedSize()
                        .foregroundStyle(section == s ? T.text : T.dim)
                    if s == .kitchen, store.tickets.contains(where: { $0.status == .new }) {
                        Text("\(store.tickets.filter { $0.status == .new }.count)").font(T.mono(11, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(height: 18).background(T.text, in: Capsule())
                    }
                    }
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(section == s ? Color.white.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: section == s ? .black.opacity(0.06) : .clear, radius: 3, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(s.shortcut, modifiers: .command)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(store.connected ? T.green : T.amber).frame(width: 7, height: 7)
                Text(store.connected ? "Online" : "Connecting").font(T.sans(13)).foregroundStyle(T.dim).fixedSize()
            }
            Button { openWindow(id: "customer") } label: { Image(systemName: "display").frame(width: 30, height: 30) }
                .buttonStyle(.plain).help("Open customer display")
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
                .padding(.leading, 12)
            Button { showHow = true } label: { Image(systemName: "questionmark").frame(width: 30, height: 30) }
                .buttonStyle(.plain).help("How Tapnad works")
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.rule))
        }
        .sheet(isPresented: $showHow) { HowItWorks() }
        .padding(.leading, 76).padding(.trailing, 14)
        .frame(height: 50)
        .glass(radius: 16, strong: true)
    }
}

/// Non-register sections sit in one large glass panel; the register lays out its own panels.
struct SectionPanel: ViewModifier {
    let isRegister: Bool
    func body(content: Content) -> some View {
        if isRegister { content } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .glass(radius: 20)
        }
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
