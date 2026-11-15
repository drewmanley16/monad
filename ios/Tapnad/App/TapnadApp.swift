import SwiftUI

@main
struct TapnadApp: App {
    @StateObject private var store = WalletStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if let req = PaymentRequest(url: url) { store.present(req) }
                }
        }
    }
}

extension Color {
    static let monadPurple = Color(red: 0.514, green: 0.431, blue: 0.976)   // #836EF9
    static let monadDeep = Color(red: 0.125, green: 0.0, blue: 0.322)       // #200052
    static let monadBerry = Color(red: 0.627, green: 0.0, blue: 0.376)      // #A0055D-ish
}
