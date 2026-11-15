import SwiftUI
import Charts
import CoreImage.CIFilterBuiltins

@main
struct POSApp: App {
    @StateObject private var store = POSStore()

    var body: some Scene {
        WindowGroup("Tapnad POS") {
            RootView()
                .environmentObject(store)
                .tint(Brand.indigo)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}

enum NavSection: String, CaseIterable, Identifiable {
    case register = "Register", activity = "Activity", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .register: "square.grid.2x2"
        case .activity: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: POSStore
    @State private var section: NavSection? = .register

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "hexagon.fill").foregroundStyle(Brand.purple.gradient)
                    Text("tapnad").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("POS").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)

                List(NavSection.allCases, selection: $section) { s in
                    Label(s.rawValue, systemImage: s.icon).tag(s)
                }
                .listStyle(.sidebar)

                ChainStatus().padding(12)
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                switch section ?? .register {
                case .register: RegisterView()
                case .activity: ActivityView()
                case .settings: POSSettingsView()
                }
            }
        }
    }
}

// MARK: - Chain status (sidebar footer)

struct ChainStatus: View {
    @EnvironmentObject var store: POSStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(store.connected ? Brand.success : .orange).frame(width: 7, height: 7)
                    .shadow(color: store.connected ? Brand.success : .clear, radius: 4)
                Text(Chain.name).font(.caption.weight(.semibold))
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.blockNumber == 0 ? "—" : "#\(store.blockNumber.formatted())")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .contentTransition(.numericText())
                    Text("Block").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.blockTimeMs.map { "\($0) ms" } ?? "—").font(.system(.caption, design: .monospaced).weight(.medium))
                    Text("Block time").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
