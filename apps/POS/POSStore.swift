import Foundation
import SwiftUI
import AppKit

struct Product: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let price: Wei
    let tint: Color

    static let catalog: [Product] = [
        .init(id: "espresso", name: "Espresso", symbol: "cup.and.saucer.fill", price: MON.parse("0.02")!, tint: .brown),
        .init(id: "latte", name: "Oat Latte", symbol: "mug.fill", price: MON.parse("0.035")!, tint: .orange),
        .init(id: "matcha", name: "Matcha", symbol: "leaf.fill", price: MON.parse("0.04")!, tint: .green),
        .init(id: "coldbrew", name: "Cold Brew", symbol: "takeoutbag.and.cup.and.straw.fill", price: MON.parse("0.03")!, tint: .indigo),
        .init(id: "croissant", name: "Croissant", symbol: "birthday.cake.fill", price: MON.parse("0.025")!, tint: .yellow),
        .init(id: "bagel", name: "Bagel", symbol: "circle.circle.fill", price: MON.parse("0.02")!, tint: .pink),
        .init(id: "water", name: "Sparkling", symbol: "drop.fill", price: MON.parse("0.01")!, tint: .cyan),
        .init(id: "merch", name: "Nad Tee", symbol: "tshirt.fill", price: MON.parse("0.25")!, tint: .purple),
    ]
}

struct Sale: Identifiable, Codable, Hashable {
    var id: String { event.invoiceId }
    let event: PaidEvent
    let date: Date
    var states: [String: Double]   // CommitState.rawValue -> seconds since first seen
    var finalizedMs: Int? { states[CommitState.finalized.rawValue].map { Int($0 * 1000) } }
}

@MainActor
final class POSStore: ObservableObject {
    // Settings
    @AppStorage("pos.name") var merchantName = "Tapnad Café" { didSet { beacon.name = merchantName } }
    @AppStorage("pos.payout") var payout = "0x2bbf6125b26B771098836f981F0588A943641b6B"

    // Register
    @Published var cart: [String: Int] = [:]
    @Published var customAmount: Wei?
    @Published var charge: Charge = .idle
    @Published var stateMs: [CommitState: Int] = [:]

    // Ledger
    @Published var sales: [Sale] = []

    // Chain
    @Published var connected = false
    @Published var blockNumber: Int = 0
    @Published var blockTimeMs: Int?
    @Published var recentBlocks: [(id: String, number: Int, state: CommitState, txs: Int)] = []

    enum Charge: Equatable {
        case idle
        case awaiting(PaymentRequest)
        case paid(PaymentRequest, PaidEvent)
    }

    let beacon = TapBeacon()
    private var stream: MonadStream?
    private var firstSeen: [String: Date] = [:]
    private var lastProposed: Date?
    private var blockTimes: [Double] = []
    private let salesKey = "pos.sales"

    init() {
        beacon.name = merchantName
        if let d = UserDefaults.standard.data(forKey: salesKey),
           let s = try? JSONDecoder().decode([Sale].self, from: d) { sales = s }
        connect()
    }

    // MARK: Cart

    var lines: [(product: Product, qty: Int)] {
        Product.catalog.compactMap { p in cart[p.id].map { (p, $0) } }
    }
    var total: Wei {
        lines.reduce(customAmount ?? 0) { $0 + $1.product.price * Wei($1.qty) }
    }
    var itemCount: Int { lines.reduce(0) { $0 + $1.qty } + (customAmount == nil ? 0 : 1) }

    func add(_ p: Product) { withAnimation(.snappy) { cart[p.id, default: 0] += 1 } }
    func decrement(_ p: Product) {
        withAnimation(.snappy) {
            if let q = cart[p.id], q > 1 { cart[p.id] = q - 1 } else { cart[p.id] = nil }
        }
    }
    func clear() { withAnimation(.snappy) { cart = [:]; customAmount = nil } }

    var memo: String {
        var parts = lines.map { $0.qty > 1 ? "\($0.qty)× \($0.product.name)" : $0.product.name }
        if customAmount != nil { parts.append("Custom") }
        return parts.joined(separator: ", ")
    }

    // MARK: Charge

    func startCharge() {
        guard total > 0, isAddress(payout) else { return }
        let req = PaymentRequest(merchant: payout, amount: total, memo: memo, merchantName: merchantName)
        stateMs = [:]
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { charge = .awaiting(req) }
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
                blockTimes.append(now.timeIntervalSince(last)); if blockTimes.count > 20 { blockTimes.removeFirst() }
                blockTimeMs = Int(blockTimes.reduce(0, +) / Double(blockTimes.count) * 1000)
            }
            lastProposed = now
        }
        let gasUsed = Int((h["gasUsed"] as? String).flatMap { Wei(hexString: $0) } ?? 0)
        if let i = recentBlocks.firstIndex(where: { $0.id == id }) {
            recentBlocks[i].state = state
        } else {
            recentBlocks.insert((id, num, state, gasUsed), at: 0)
            if recentBlocks.count > 7 { recentBlocks.removeLast() }
        }
    }

    private func onLog(_ log: [String: Any]) {
        guard let ev = PaidEvent(log: log), let cs = log["commitState"] as? String,
              let state = CommitState(rawValue: cs) else { return }
        let now = Date()
        let first = firstSeen[ev.invoiceId] ?? now
        firstSeen[ev.invoiceId] = first
        let elapsed = now.timeIntervalSince(first)

        // ledger
        if let i = sales.firstIndex(where: { $0.id == ev.invoiceId }) {
            for s in CommitState.timeline where s.rank <= state.rank && sales[i].states[s.rawValue] == nil {
                sales[i].states[s.rawValue] = elapsed
            }
        } else {
            var states: [String: Double] = [:]
            for s in CommitState.timeline where s.rank <= state.rank { states[s.rawValue] = elapsed }
            withAnimation(.snappy) { sales.insert(Sale(event: ev, date: now, states: states), at: 0) }
        }
        saveSales()

        // active charge
        if case .awaiting(let req) = charge, req.invoiceId.hex.lowercased() == ev.invoiceId {
            beacon.publish(nil)
            NSSound(named: "Glass")?.play()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { charge = .paid(req, ev) }
        }
        if case .paid(let req, _) = charge, req.invoiceId.hex.lowercased() == ev.invoiceId {
            for s in CommitState.timeline where s.rank <= state.rank && stateMs[s] == nil {
                withAnimation(.spring(duration: 0.35)) { stateMs[s] = Int(elapsed * 1000) }
            }
        }
    }

    private func saveSales() {
        if let d = try? JSONEncoder().encode(Array(sales.prefix(200))) { UserDefaults.standard.set(d, forKey: salesKey) }
    }

    // MARK: Stats

    var grossVolume: Wei { sales.reduce(0) { $0 + $1.event.amount } }
    var avgFinalityMs: Int? {
        let f = sales.compactMap(\.finalizedMs).filter { $0 > 0 }
        return f.isEmpty ? nil : f.reduce(0, +) / f.count
    }
}
