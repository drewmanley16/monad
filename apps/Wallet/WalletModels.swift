import SwiftUI

// MARK: - Card themes

enum CardTheme: String, Codable, CaseIterable, Identifiable {
    case monad, midnight, aurora, sunset, graphite, lime
    var id: String { rawValue }

    // Raw values kept for saved data; presented as plain, solid finishes.
    var name: String {
        switch self {
        case .monad: "Violet"
        case .midnight: "Black"
        case .aurora: "Slate"
        case .sunset: "Clay"
        case .graphite: "Silver"
        case .lime: "Sage"
        }
    }

    var color: Color {
        switch self {
        case .monad: Color(red: 0.42, green: 0.36, blue: 0.82)
        case .midnight: Color(red: 0.11, green: 0.11, blue: 0.12)
        case .aurora: Color(red: 0.27, green: 0.33, blue: 0.40)
        case .sunset: Color(red: 0.66, green: 0.42, blue: 0.33)
        case .graphite: Color(red: 0.80, green: 0.80, blue: 0.79)
        case .lime: Color(red: 0.55, green: 0.62, blue: 0.52)
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom) }
    var foreground: Color { self == .graphite ? Color.black.opacity(0.82) : .white }
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
        case .food: Color(red: 0.80, green: 0.55, blue: 0.35)
        case .shopping: Color(red: 0.72, green: 0.45, blue: 0.52)
        case .travel: Color(red: 0.38, green: 0.60, blue: 0.62)
        case .office: Color(red: 0.42, green: 0.52, blue: 0.75)
        case .entertainment: Color(red: 0.58, green: 0.48, blue: 0.72)
        case .other: Color(red: 0.55, green: 0.55, blue: 0.57)
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
