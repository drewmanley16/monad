import Foundation
import SwiftUI
import AppKit

// MARK: - Models

enum ProductCategory: String, Codable, CaseIterable, Identifiable {
    case coffee = "Coffee", tea = "Tea", food = "Food", drinks = "Drinks", merch = "Merch"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .coffee: "cup.and.saucer.fill"
        case .tea: "leaf.fill"
        case .food: "fork.knife"
        case .drinks: "waterbottle.fill"
        case .merch: "tshirt.fill"
        }
    }

}

struct Product: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String
    var category: ProductCategory
    var priceWei: String
    var price: Wei { Wei(priceWei) ?? 0 }

    init(id: String = UUID().uuidString, _ name: String, _ emoji: String, _ cat: ProductCategory, _ price: String) {
        self.id = id; self.name = name; self.emoji = emoji; self.category = cat
        self.priceWei = String(MON.parse(price) ?? 0)
    }

    static let defaults: [Product] = [
        .init("Espresso", "☕️", .coffee, "0.02"),
        .init("Oat Latte", "🥛", .coffee, "0.035"),
        .init("Cold Brew", "🧊", .coffee, "0.03"),
        .init("Cortado", "🤎", .coffee, "0.03"),
        .init("Matcha Latte", "🍵", .tea, "0.04"),
        .init("Chai", "🫖", .tea, "0.032"),
        .init("Croissant", "🥐", .food, "0.025"),
        .init("Everything Bagel", "🥯", .food, "0.02"),
        .init("Avo Toast", "🥑", .food, "0.06"),
        .init("Sparkling Water", "💧", .drinks, "0.01"),
        .init("Orange Juice", "🍊", .drinks, "0.028"),
        .init("Nad Tee", "👕", .merch, "0.25"),
        .init("Purple Cap", "🧢", .merch, "0.18"),
    ]
}

struct OrderLine: Codable, Hashable {
    let name: String
    let emoji: String
    let qty: Int
    let unitWei: String
    var unit: Wei { Wei(unitWei) ?? 0 }
}

struct Sale: Identifiable, Codable, Hashable {
    var id: String { event.invoiceId }
    let event: PaidEvent
    let date: Date
    var states: [String: Double]          // CommitState.rawValue -> seconds since first sighting
    var lines: [OrderLine]?
    var tipWei: String?

    var finalizedMs: Int? { states[CommitState.finalized.rawValue].map { Int($0 * 1000) } }
    var votedMs: Int? { states[CommitState.voted.rawValue].map { Int($0 * 1000) } }
    var tip: Wei { tipWei.flatMap { Wei($0) } ?? 0 }
    var latestState: CommitState {
        states[CommitState.finalized.rawValue] != nil ? .finalized : states[CommitState.voted.rawValue] != nil ? .voted : .proposed
    }
}

struct Customer: Identifiable {
    var id: String { address }
    let address: String
    let sales: [Sale]
    var total: Wei { sales.reduce(0) { $0 + $1.event.amount } }
    var visits: Int { sales.count }
    var lastSeen: Date { sales.map(\.date).max() ?? .distantPast }
    var favorite: String? {
        let counts = sales.flatMap { $0.lines ?? [] }.reduce(into: [String: Int]()) { $0[$1.emoji + " " + $1.name, default: 0] += $1.qty }
        return counts.max { $0.value < $1.value }?.key
    }
    var tier: (name: String, color: Color) {
        if visits >= 5 || total >= MON.parse("1")! { return ("VIP", T.amber) }
        if visits >= 2 { return ("Regular", T.accent) }
        return ("New", T.green)
    }
}

// MARK: - Store

@MainActor
final class POSStore: ObservableObject {
    // Settings
    @AppStorage("pos.name") var merchantName = "Tapnad Café" { didSet { beacon.name = merchantName } }
    @AppStorage("pos.payout") var payout = "0x2bbf6125b26B771098836f981F0588A943641b6B"

    // Catalog
    @Published var catalog: [Product] = [] { didSet { saveCatalog() } }

    // Register
    @Published var cart: [String: Int] = [:]
    @Published var customAmount: Wei?
    @Published var tipPercent: Int = 0
    @Published var search = ""
    @Published var categoryFilter: ProductCategory?
    @Published var charge: Charge = .idle
    @Published var stateMs: [CommitState: Int] = [:]

    // Ledger
    @Published var sales: [Sale] = []

    // Chain
    @Published var connected = false
    @Published var blockNumber: Int = 0
    @Published var blockTimeMs: Int?
    @Published var blockTimeHistory: [Double] = []
    @Published var recentBlocks: [BlockRow] = []

    struct BlockRow: Identifiable, Equatable { let id: String; let number: Int; var state: CommitState; let gas: Int; let seen: Date }

    enum Charge: Equatable {
        case idle
        case awaiting(PaymentRequest)
        case paid(PaymentRequest, PaidEvent)
    }

    let beacon = TapBeacon()
    private var stream: MonadStream?
    private var firstSeen: [String: Date] = [:]
    private var pendingOrders: [String: (lines: [OrderLine], tip: Wei)] = [:]
    private var lastProposed: Date?

    init() {
        beacon.name = merchantName
        let d = UserDefaults.standard
        if let data = d.data(forKey: "pos.sales"), let s = try? JSONDecoder().decode([Sale].self, from: data) { sales = s }
        if let data = d.data(forKey: "pos.catalog"), let c = try? JSONDecoder().decode([Product].self, from: data), !c.isEmpty {
            catalog = c
        } else {
            catalog = Product.defaults
        }
        connect()
    }

    // MARK: Cart

    var visibleProducts: [Product] {
        catalog.filter { p in
            (categoryFilter == nil || p.category == categoryFilter) &&
            (search.isEmpty || p.name.localizedCaseInsensitiveContains(search))
        }
    }

    var lines: [(product: Product, qty: Int)] { catalog.compactMap { p in cart[p.id].map { (p, $0) } } }
    var subtotal: Wei { lines.reduce(customAmount ?? 0) { $0 + $1.product.price * Wei($1.qty) } }
    var tip: Wei { subtotal * Wei(tipPercent) / 100 }
    var total: Wei { subtotal + tip }
    var itemCount: Int { lines.reduce(0) { $0 + $1.qty } + (customAmount == nil ? 0 : 1) }

    func add(_ p: Product) { withAnimation(.snappy) { cart[p.id, default: 0] += 1 } }
    func decrement(_ p: Product) {
        withAnimation(.snappy) { if let q = cart[p.id], q > 1 { cart[p.id] = q - 1 } else { cart[p.id] = nil } }
    }
    func clear() { withAnimation(.snappy) { cart = [:]; customAmount = nil; tipPercent = 0 } }

    private var memo: String {
        var parts = lines.map { $0.qty > 1 ? "\($0.qty)× \($0.product.name)" : $0.product.name }
        if customAmount != nil { parts.append("Custom") }
        if tipPercent > 0 { parts.append("Tip \(tipPercent)%") }
        return parts.joined(separator: ", ")
    }

    // MARK: Catalog CRUD

    func upsert(_ p: Product) {
        if let i = catalog.firstIndex(where: { $0.id == p.id }) { catalog[i] = p } else { catalog.append(p) }
    }
    func remove(_ p: Product) { catalog.removeAll { $0.id == p.id }; cart[p.id] = nil }
    func unitsSold(_ p: Product) -> Int {
        sales.flatMap { $0.lines ?? [] }.filter { $0.name == p.name }.reduce(0) { $0 + $1.qty }
    }

    // MARK: Charge

    func startCharge() {
        guard total > 0, isAddress(payout) else { return }
        let req = PaymentRequest(merchant: payout, amount: total, memo: memo, merchantName: merchantName)
        var orderLines = lines.map { OrderLine(name: $0.product.name, emoji: $0.product.emoji, qty: $0.qty, unitWei: $0.product.priceWei) }
        if let c = customAmount { orderLines.append(OrderLine(name: "Custom amount", emoji: "✏️", qty: 1, unitWei: String(c))) }
        pendingOrders[req.invoiceId.hex.lowercased()] = (orderLines, tip)
        stateMs = [:]
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { charge = .awaiting(req) }
        beacon.publish(req)
    }

    func cancelCharge() {
        beacon.publish(nil)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { charge = .idle }
    }

    func newSale() {
        beacon.publish(nil)
        clear()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { charge = .idle }
    }

    // MARK: Chain stream

    func connect() {
        stream?.stop()
        let s = MonadStream()
        stream = s
        s.onConnectionChange = { [weak self] ok in self?.connected = ok }
        s.subscribe(["monadNewHeads"]) { [weak self] head in self?.onHead(head) }
        if isAddress(payout) {
            s.subscribe(["monadLogs", ["address": Chain.monadPay,
                                       "topics": [MonadPayABI.paidTopic, MonadPayABI.topic(address: payout)]]]) { [weak self] log in
                self?.onLog(log)
            }
        }
        s.connect()
    }

    private func onHead(_ h: [String: Any]) {
        guard let numHex = h["number"] as? String, let n = Wei(hexString: numHex),
              let cs = h["commitState"] as? String, let state = CommitState(rawValue: cs),
              let id = h["blockId"] as? String else { return }
        let num = Int(n)
        if num > blockNumber { blockNumber = num }
        if state == .proposed {
            let now = Date()
            if let last = lastProposed {
                let dt = now.timeIntervalSince(last) * 1000
                if dt < 3000 {
                    blockTimeHistory.append(dt); if blockTimeHistory.count > 40 { blockTimeHistory.removeFirst() }
                    blockTimeMs = Int(blockTimeHistory.suffix(15).reduce(0, +) / Double(min(15, blockTimeHistory.count)))
                }
            }
            lastProposed = now
        }
        let gas = Int((h["gasUsed"] as? String).flatMap { Wei(hexString: $0) } ?? 0)
        if let i = recentBlocks.firstIndex(where: { $0.id == id }) {
            if state.rank > recentBlocks[i].state.rank { recentBlocks[i].state = state }
        } else if state == .proposed {
            recentBlocks.insert(BlockRow(id: id, number: num, state: state, gas: gas, seen: Date()), at: 0)
            if recentBlocks.count > 9 { recentBlocks.removeLast() }
        }
    }

    private func onLog(_ log: [String: Any]) {
        guard let ev = PaidEvent(log: log), let cs = log["commitState"] as? String,
              let state = CommitState(rawValue: cs) else { return }
        let now = Date()
        let first = firstSeen[ev.invoiceId] ?? now
        firstSeen[ev.invoiceId] = first
        let elapsed = now.timeIntervalSince(first)

        if let i = sales.firstIndex(where: { $0.id == ev.invoiceId }) {
            for s in CommitState.timeline where s.rank <= state.rank && sales[i].states[s.rawValue] == nil {
                sales[i].states[s.rawValue] = elapsed
            }
        } else {
            var states: [String: Double] = [:]
            for s in CommitState.timeline where s.rank <= state.rank { states[s.rawValue] = elapsed }
            let order = pendingOrders.removeValue(forKey: ev.invoiceId)
            let sale = Sale(event: ev, date: now, states: states, lines: order?.lines, tipWei: order.map { String($0.tip) })
            withAnimation(.snappy) { sales.insert(sale, at: 0) }
        }
        saveSales()

        if case .awaiting(let req) = charge, req.invoiceId.hex.lowercased() == ev.invoiceId {
            beacon.publish(nil)
            NSSound(named: "Glass")?.play()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { charge = .paid(req, ev) }
        }
        if case .paid(let req, _) = charge, req.invoiceId.hex.lowercased() == ev.invoiceId {
            for s in CommitState.timeline where s.rank <= state.rank && stateMs[s] == nil {
                withAnimation(.spring(duration: 0.35)) { stateMs[s] = Int(elapsed * 1000) }
            }
        }
    }

    // MARK: Analytics

    var grossVolume: Wei { sales.reduce(0) { $0 + $1.event.amount } }
    var tipsTotal: Wei { sales.reduce(0) { $0 + $1.tip } }
    var avgTicket: Wei { sales.isEmpty ? 0 : grossVolume / Wei(sales.count) }
    var avgFinalityMs: Int? {
        let f = sales.compactMap(\.finalizedMs).filter { $0 > 0 }
        return f.isEmpty ? nil : f.reduce(0, +) / f.count
    }
    var todaySales: [Sale] { sales.filter { Calendar.current.isDateInToday($0.date) } }

    var customers: [Customer] {
        Dictionary(grouping: sales) { $0.event.payer.lowercased() }
            .map { Customer(address: $0.value.first!.event.payer, sales: $0.value) }
            .sorted { $0.total > $1.total }
    }

    var topProducts: [(name: String, emoji: String, qty: Int, revenue: Double)] {
        var agg: [String: (String, Int, Double)] = [:]
        for l in sales.flatMap({ $0.lines ?? [] }) {
            let cur = agg[l.name] ?? (l.emoji, 0, 0)
            agg[l.name] = (l.emoji, cur.1 + l.qty, cur.2 + Double(l.unit * Wei(l.qty)) / 1e18)
        }
        return agg.map { ($0.key, $0.value.0, $0.value.1, $0.value.2) }.sorted { $0.revenue > $1.revenue }
    }

    // MARK: Persistence

    private func saveSales() {
        if let d = try? JSONEncoder().encode(Array(sales.prefix(500))) { UserDefaults.standard.set(d, forKey: "pos.sales") }
    }
    private func saveCatalog() {
        if let d = try? JSONEncoder().encode(catalog) { UserDefaults.standard.set(d, forKey: "pos.catalog") }
    }
    func resetSales() { sales = []; saveSales() }
}
