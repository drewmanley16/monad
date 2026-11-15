import SwiftUI

@main
struct WalletApp: App {
    @StateObject private var store = WalletStore()
    @State private var deepLink: PaymentRequest?
    @State private var showTap = false

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Wallet", systemImage: "wallet.bifold.fill") { HomeView(showTap: $showTap) }
                Tab("Activity", systemImage: "list.bullet.rectangle.portrait.fill") { ActivityView() }
                Tab("Insights", systemImage: "chart.pie.fill") { InsightsView() }
            }
            .environmentObject(store)
            .tint(.primary)
            .fullScreenCover(isPresented: $showTap, onDismiss: { store.endPayment(); deepLink = nil }) {
                TapToPayView(preloaded: deepLink).environmentObject(store)
            }
            .onOpenURL { url in
                if let req = PaymentRequest(url: url) { deepLink = req; showTap = true }
            }
            .task {
                await store.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    await store.refresh()
                }
            }
        }
    }
}
