import SwiftUI

// MARK: - Card themes

enum CardTheme: String, Codable, CaseIterable, Identifiable {
    case monad, midnight, aurora, sunset, graphite, lime
    var id: String { rawValue }

    var name: String {
        switch self {
        case .monad: "Monad"
        case .midnight: "Midnight"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .graphite: "Titanium"
        case .lime: "Volt"
        }
    }

    var colors: [Color] {
        switch self {
        case .monad: [Color(red: 0.55, green: 0.45, blue: 1.0), Color(red: 0.36, green: 0.22, blue: 0.86), Brand.deep]
        case .midnight: [Color(red: 0.16, green: 0.16, blue: 0.2), Color(red: 0.06, green: 0.06, blue: 0.08), .black]
        case .aurora: [Color(red: 0.2, green: 0.85, blue: 0.8), Color(red: 0.15, green: 0.45, blue: 0.95), Color(red: 0.2, green: 0.1, blue: 0.5)]
        case .sunset: [Color(red: 1.0, green: 0.62, blue: 0.3), Color(red: 0.95, green: 0.3, blue: 0.45), Color(red: 0.45, green: 0.12, blue: 0.5)]
        case .graphite: [Color(red: 0.82, green: 0.82, blue: 0.84), Color(red: 0.55, green: 0.56, blue: 0.6), Color(red: 0.3, green: 0.31, blue: 0.34)]
        case .lime: [Color(red: 0.85, green: 1.0, blue: 0.35), Color(red: 0.35, green: 0.8, blue: 0.4), Color(red: 0.05, green: 0.3, blue: 0.25)]
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    var glow: Color { colors[1] }
    var foreground: Color { self == .graphite || self == .lime ? Color.black.opacity(0.85) : .white }
}

// MARK: - Cards (each card = its own on-device key)

struct CardAccount: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var theme: CardTheme
    var isBusiness: Bool
    let address: String
}

// MARK: - Expense categories

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case food, shopping, travel, office, entertainment, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .food: "Food & Drink"
        case .shopping: "Shopping"
        case .travel: "Travel"
        case .office: "Office & Software"
        case .entertainment: "Entertainment"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .food: "fork.knife"
        case .shopping: "bag.fill"
        case .travel: "airplane"
        case .office: "laptopcomputer"
        case .entertainment: "sparkles.tv.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .food: .orange
        case .shopping: .pink
        case .travel: .teal
        case .office: .blue
        case .entertainment: .purple
        case .other: .gray
        }
    }

    /// Best-guess category from merchant name + items.
    static func guess(merchant: String, memo: String) -> ExpenseCategory {
        let s = (merchant + " " + memo).lowercased()
        let table: [(ExpenseCategory, [String])] = [
            (.food, ["café", "cafe", "coffee", "latte", "espresso", "matcha", "brew", "bagel", "croissant", "food", "pizza", "burger", "bar", "kitchen", "tea", "sparkling", "water"]),
            (.travel, ["uber", "lyft", "air", "hotel", "train", "taxi", "transit", "gas"]),
            (.office, ["office", "software", "cloud", "print", "supply", "saas"]),
            (.entertainment, ["cinema", "movie", "concert", "game", "ticket", "club"]),
            (.shopping, ["tee", "shirt", "merch", "store", "shop", "hoodie"]),
        ]
        for (cat, words) in table where words.contains(where: s.contains) { return cat }
        return .other
    }
}

// MARK: - Payment record

struct PaymentRecord: Codable, Identifiable, Hashable {
    var id: String { txHash }
    let txHash: String
    let merchantName: String
    var merchant: String?
    let memo: String
    let amountWei: String
    let date: Date
    var proposedMs: Int?
    var votedMs: Int?
    var finalizedMs: Int?
    var cardId: UUID?
    var category: ExpenseCategory?
    var note: String?
    var feeWei: String?

    var amount: Wei { Wei(amountWei) ?? 0 }
    var fee: Wei { feeWei.flatMap { Wei($0) } ?? 0 }
    var resolvedCategory: ExpenseCategory { category ?? .guess(merchant: merchantName, memo: memo) }

    /// "2× Oat Latte, Croissant" → [(2, "Oat Latte"), (1, "Croissant")]
    var items: [(qty: Int, name: String)] {
        memo.split(separator: ",").map { raw in
            let s = raw.trimmingCharacters(in: .whitespaces)
            if let x = s.firstIndex(of: "×"), let q = Int(s[..<x].trimmingCharacters(in: .whitespaces)) {
                return (q, s[s.index(after: x)...].trimmingCharacters(in: .whitespaces))
            }
            return (1, s)
        }.filter { !$0.name.isEmpty }
    }
}

extension Wei {
    var monDouble: Double { Double(self) / 1e18 }
}
