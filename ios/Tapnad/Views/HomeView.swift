import SwiftUI
import VisionKit

struct HomeView: View {
    @EnvironmentObject var store: WalletStore
    @State private var nfc = NFCReader()
    @State private var showScanner = false
    @State private var showReceive = false
    @State private var showSettings = false
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CardView(balance: store.balance, address: store.address)
                        .padding(.top, 8)
                        .onTapGesture { showReceive = true }

                    tapButton

                    HStack(spacing: 12) {
                        action("qrcode.viewfinder", "Scan") { showScanner = true }
                        action("arrow.down.circle", "Add MON") { showReceive = true }
                    }

                    activity
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .sheet(item: Binding(get: { store.pending }, set: { if $0 == nil { store.dismissPayment() } })) { _ in
                PaySheet().environmentObject(store)
                    .presentationDetents([.large])
                    .presentationBackground(.black)
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { url in
                    showScanner = false
                    if let req = PaymentRequest(url: url) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.present(req) }
                    }
                }
            }
            .sheet(isPresented: $showReceive) { ReceiveView().environmentObject(store) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        }
    }

    private var tapButton: some View {
        Button {
            Haptics.tap()
            nfc.read { url in
                if let url, let req = PaymentRequest(url: url) {
                    store.present(req.freshInvoiceIfStatic(fromTag: true))
                }
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.monadPurple.opacity(0.5), lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(pulse ? 1.25 : 0.9).opacity(pulse ? 0 : 1)
                    Image(systemName: "wave.3.right").font(.system(size: 20, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap to Pay").font(.headline)
                    Text("Hold near a Tapnad reader").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
    }

    private func action(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest Transactions").font(.title3.weight(.semibold))
            if store.history.isEmpty {
                Text("Your payments show up here.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18).background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.history.prefix(12).enumerated()), id: \.element.id) { i, rec in
                        Link(destination: URL(string: Chain.explorerTx + rec.txHash)!) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.monadPurple.opacity(0.25)).frame(width: 40, height: 40)
                                    Text(String(rec.merchantName.prefix(1))).font(.headline)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rec.merchantName).font(.body.weight(.medium))
                                    Text(sub(rec)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("−\(MON.format(rec.amount)) MON").font(.body.monospacedDigit())
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if i < min(store.history.count, 12) - 1 { Divider().padding(.leading, 68) }
                    }
                }
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func sub(_ r: PaymentRecord) -> String {
        var s = r.date.formatted(.relative(presentation: .named))
        if let ms = r.proposedMs { s += " · confirmed in \(ms) ms" }
        return s
    }
}

// MARK: - QR scanner

struct QRScannerSheet: View {
    let onURL: (URL) -> Void
    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported {
                    QRScanner(onURL: onURL).ignoresSafeArea()
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera")
                }
            }
            .navigationTitle("Scan to Pay").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    let onURL: (URL) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .fast, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onURL: onURL) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onURL: (URL) -> Void
        var fired = false
        init(onURL: @escaping (URL) -> Void) { self.onURL = onURL }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items {
                if !fired, let str = b.payloadStringValue, let url = URL(string: str), PaymentRequest(url: url) != nil {
                    fired = true; Haptics.tap(); onURL(url)
                }
            }
        }
    }
}
