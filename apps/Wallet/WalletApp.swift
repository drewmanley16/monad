import SwiftUI

@main
struct WalletApp: App {
    @StateObject private var store = WalletStore()
    @State private var deepLink: PaymentRequest?

    var body: some Scene {
        WindowGroup {
            HomeView(deepLink: $deepLink)
                .environmentObject(store)
                .tint(Brand.purple)
                .onOpenURL { url in deepLink = PaymentRequest(url: url) }
        }
    }
}
