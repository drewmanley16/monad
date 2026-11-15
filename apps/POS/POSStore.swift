import Foundation
import SwiftUI
import AppKit

// MARK: - Catalog

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
    /// Counts toward loyalty stamps.
    var isDrink: Bool { self == .coffee || self == .tea }
    var hasOptions: Bool { self == .coffee || self == .tea }
}

struct Product: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String
    var category: ProductCategory
    var priceWei: String
    var stock: Int?                  // nil = untracked
    var price: Wei { Wei(priceWei) ?? 0 }
    var soldOut: Bool { (stock ?? 1) <= 0 }

    init(id: String = UUID().uuidString, _ name: String, _ emoji: String, _ cat: ProductCategory, _ price: String, stock: Int? = nil) {
        self.id = id; self.name = name; self.emoji = emoji; self.category = cat
        self.priceWei = String(MON.parse(price) ?? 0)
        self.stock = stock
    }

    static let defaults: [Product] = [
        .init("Espresso", "", .coffee, "0.02"),
        .init("Oat Latte", "", .coffee, "0.035"),
        .init("Cold Brew", "", .coffee, "0.03"),
        .init("Cortado", "", .coffee, "0.03"),
        .init("Matcha Latte", "", .tea, "0.04"),
        .init("Chai", "", .tea, "0.032"),
        .init("Croissant", "", .food, "0.025", stock: 12),
        .init("Everything Bagel", "", .food, "0.02", stock: 10),
        .init("Avo Toast", "", .food, "0.06", stock: 8),
        .init("Sparkling Water", "", .drinks, "0.01"),
        .init("Orange Juice", "", .drinks, "0.028"),
        .init("Nad Tee", "", .merch, "0.25", stock: 20),
        .init("Purple Cap", "", .merch, "0.18", stock: 15),
    ]

    static let restaurant: [Product] = [
        .init("Burger", "", .food, "0.14"), .init("Fries", "", .food, "0.05"), .init("Caesar Salad", "", .food, "0.12"),
        .init("Margherita Pizza", "", .food, "0.16"), .init("Tacos", "", .food, "0.11"),
        .init("Lemonade", "", .drinks, "0.04"), .init("Iced Tea", "", .tea, "0.035"), .init("Sparkling Water", "", .drinks, "0.02"),
        .init("Espresso", "", .coffee, "0.03"), .init("Brownie", "", .food, "0.06"),
    ]

    static let retail: [Product] = [
        .init("T-Shirt", "", .merch, "0.25", stock: 30), .init("Hoodie", "", .merch, "0.55", stock: 15),
        .init("Cap", "", .merch, "0.20", stock: 20), .init("Tote Bag", "", .merch, "0.15", stock: 25),
        .init("Stickers", "", .merch, "0.04"), .init("Poster", "", .merch, "0.12", stock: 40),
        .init("Water", "", .drinks, "0.02"),
    ]
}

/// Drink modifiers.
struct DrinkOptions: Hashable, Codable {
    enum Size: String, CaseIterable, Codable { case small = "Small", large = "Large" }
    enum Milk: String, CaseIterable, Codable { case whole = "Whole", oat = "Oat", almond = "Almond", none = "No milk" }
    var size: Size = .small
    var milk: Milk = .whole
    var extraShot = false

    static let largeUp = MON.parse("0.01")!
    static let altMilk = MON.parse("0.005")!
    static let shot = MON.parse("0.008")!

    var surcharge: Wei {
        (size == .large ? Self.largeUp : 0) + (milk == .oat || milk == .almond ? Self.altMilk : 0) + (extraShot ? Self.shot : 0)
    }
    var summary: String {
        var parts: [String] = []
        if size == .large { parts.append("Large") }
        if milk != .whole { parts.append(milk.rawValue + (milk == .none ? "" : " milk")) }
        if extraShot { parts.append("Extra shot") }
        return parts.joined(separator: ", ")
    }
}

struct CartLine: Identifiable, Hashable {
    let id = UUID()
    let product: Product
    var options: DrinkOptions?
    var qty: Int
    var unit: Wei { product.price + (options?.surcharge ?? 0) }
    var total: Wei { unit * Wei(qty) }
    var title: String { product.name }
    var detail: String? { options.flatMap { $0.summary.isEmpty ? nil : $0.summary } }
}

// MARK: - Ledger

struct OrderLine: Codable, Hashable {
    let name: String
    let emoji: String
    let qty: Int
    let unitWei: String
    var options: String?
    var isDrink: Bool?
    var unit: Wei { Wei(unitWei) ?? 0 }
}

struct Sale: Identifiable, Codable, Hashable {
    var id: String { event.invoiceId }
    let event: PaidEvent
    let date: Date
    var states: [String: Double]
    var lines: [OrderLine]?
    var tipWei: String?
    var orderNumber: Int?
    var splitPart: String?           // "2/3"
    var refundTx: String?
    var rewardApplied: String?

    var finalizedMs: Int? { states[CommitState.finalized.rawValue].map { Int($0 * 1000) } }
    var tip: Wei { tipWei.flatMap { Wei($0) } ?? 0 }
    var latestState: CommitState {
        states[CommitState.finalized.rawValue] != nil ? .finalized : states[CommitState.voted.rawValue] != nil ? .voted : .proposed
    }
    var drinkCount: Int { (lines ?? []).filter { $0.isDrink ?? false }.reduce(0) { $0 + $1.qty } }
}

enum TicketStatus: String, Codable, CaseIterable { case new = "New", preparing = "Preparing", ready = "Ready", done = "Picked up" }

struct KitchenTicket: Identifiable, Codable, Hashable {
    var id: Int { number }
    let number: Int
    let lines: [OrderLine]
    let payer: String
    let createdAt: Date
    var status: TicketStatus
}

struct Customer: Identifiable {
    var id: String { address }
    let address: String
    let sales: [Sale]
    var total: Wei { sales.reduce(0) { $0 + $1.event.amount } }
    var visits: Int { Set(sales.map { $0.orderNumber.map(String.init) ?? $0.id }).count }
    var lastSeen: Date { sales.map(\.date).max() ?? .distantPast }
    var drinks: Int { sales.reduce(0) { $0 + $1.drinkCount } }
    var stamps: Int { drinks % LoyaltyProgram.stampsForReward }
    var rewardsEarned: Int { drinks / LoyaltyProgram.stampsForReward }
    var favorite: String? {
        let counts = sales.flatMap { $0.lines ?? [] }.reduce(into: [String: Int]()) { $0[$1.name, default: 0] += $1.qty }
        return counts.max { $0.value < $1.value }?.key
    }
    var tier: (name: String, color: Color) {
        if visits >= 5 || total >= MON.parse("1")! { return ("VIP", T.text) }
        if visits >= 2 { return ("Regular", T.dim) }
        return ("New", T.faint)
    }
}

enum LoyaltyProgram { static let stampsForReward = 8 }

// MARK: - Store

@MainActor
final class POSStore: ObservableObject {
    /// Split bill is hidden until it's been rehearsed end-to-end.
    nonisolated static let splitEnabled = false

    // Settings
    @AppStorage("pos.name") var merchantName = "Tapnad Café" { didSet { beacon.name = merchantName } }
    @AppStorage("pos.payout") var payout = "0x2bbf6125b26B771098836f981F0588A943641b6B"
    @AppStorage("pos.taxPercent") var taxPercent: Double = 0

    // Catalog
    @Published var catalog: [Product] = [] { didSet { saveCatalog() } }

    // Register
    @Published var cart: [CartLine] = []
    @Published var customAmount: Wei?
    @Published var tipPercent: Int = 0
    @Published var discountPercent: Int = 0
    @Published var splitCount: Int = 1
    @Published var search = ""
    @Published var categoryFilter: ProductCategory?
    @Published var optionsFor: Product?

    // Charge
    @Published var charge: Charge = .idle
    @Published var stateMs: [CommitState: Int] = [:]
    @Published var parts: [PaymentRequest] = []
    @Published var paidParts: [PaidEvent] = []
    @Published var lastOrderNumber: Int?
    @Published var identifiedPayer: String?
    @Published var rewardNotice: String?
    @Published var refundBalance: Wei?
    @Published var refunding: String?

    // Ledger
    @Published var sales: [Sale] = []
    @Published var tickets: [KitchenTicket] = []

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
    private var pendingOrders: [String: (lines: [OrderLine], tip: Wei, number: Int, part: String?, expected: Wei, reward: String?)] = [:]
    private var pollTimer: Timer?
    private var redeemed: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "pos.redeemed") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "pos.redeemed") }
    }
    let refundAccount: EthAccount? = POSKeychain.refundAccount()
    private var lastProposed: Date?
    @AppStorage("pos.nextOrder") private var nextOrderNumber = 101

    init() {
        beacon.name = merchantName
        beacon.onIdentify = { [weak self] payer in self?.identify(payer) }
        let d = UserDefaults.standard
        if let data = d.data(forKey: "pos.sales"), let s = try? JSONDecoder().decode([Sale].self, from: data) { sales = s }
        if let data = d.data(forKey: "pos.tickets"), let t = try? JSONDecoder().decode([KitchenTicket].self, from: data) { tickets = t }
        if let data = d.data(forKey: "pos.catalog"), let c = try? JSONDecoder().decode([Product].self, from: data), !c.isEmpty {
            catalog = c
        } else {
            catalog = Product.defaults
        }
        connect()
        Task { await refreshRefundBalance() }
    }



    // MARK: Cart

    var visibleProducts: [Product] {
        catalog.filter { p in
            (categoryFilter == nil || p.category == categoryFilter) &&
            (search.isEmpty || p.name.localizedCaseInsensitiveContains(search))
        }
    }

    func qty(of p: Product) -> Int { cart.filter { $0.product.id == p.id }.reduce(0) { $0 + $1.qty } }

    var subtotal: Wei { cart.reduce(customAmount ?? 0) { $0 + $1.total } }
    var discount: Wei { subtotal * Wei(discountPercent) / 100 }
    var tax: Wei { Wei(Double(subtotal - discount) * taxPercent / 100) }
    var tip: Wei { (subtotal - discount) * Wei(tipPercent) / 100 }
    var total: Wei { subtotal - discount + tax + tip }
    var itemCount: Int { cart.reduce(0) { $0 + $1.qty } + (customAmount == nil ? 0 : 1) }

    /// Tile tap: drinks open the options sheet, everything else adds directly.
    func tap(_ p: Product) {
        guard !p.soldOut, qty(of: p) < (p.stock ?? .max) else { return }
        if p.category.hasOptions { optionsFor = p } else { add(p, options: nil) }
    }

    func add(_ p: Product, options: DrinkOptions?) {
        withAnimation(.snappy) {
            if let i = cart.firstIndex(where: { $0.product.id == p.id && $0.options == options }) { cart[i].qty += 1 }
            else { cart.append(CartLine(product: p, options: options, qty: 1)) }
        }
    }
    func increment(_ line: CartLine) {
        guard let i = cart.firstIndex(where: { $0.id == line.id }), qty(of: line.product) < (line.product.stock ?? .max) else { return }
        withAnimation(.snappy) { cart[i].qty += 1 }
    }
    func decrement(_ line: CartLine) {
        guard let i = cart.firstIndex(where: { $0.id == line.id }) else { return }
        withAnimation(.snappy) { if cart[i].qty > 1 { cart[i].qty -= 1 } else { cart.remove(at: i) } }
    }
    func clear() {
        withAnimation(.snappy) { cart = []; customAmount = nil; tipPercent = 0; discountPercent = 0; splitCount = 1 }
    }

    private var memo: String {
        var parts = cart.map { l -> String in
            let base = l.qty > 1 ? "\(l.qty)× \(l.title)" : l.title
            return l.detail.map { "\(base) (\($0))" } ?? base
        }
        if customAmount != nil { parts.append("Custom") }
        if discountPercent > 0 { parts.append("−\(discountPercent)%") }
        if tipPercent > 0 { parts.append("Tip \(tipPercent)%") }
        return parts.joined(separator: ", ")
    }

    // MARK: Catalog CRUD

    func upsert(_ p: Product) {
        if let i = catalog.firstIndex(where: { $0.id == p.id }) { catalog[i] = p } else { catalog.append(p) }
    }
    func remove(_ p: Product) { catalog.removeAll { $0.id == p.id }; cart.removeAll { $0.product.id == p.id } }
    func unitsSold(_ p: Product) -> Int {
        sales.flatMap { $0.lines ?? [] }.filter { $0.name == p.name }.reduce(0) { $0 + $1.qty }
    }

    // MARK: Charge (with optional split)

    func startCharge() {
        guard total > 0, isAddress(payout) else { return }
        let number = nextOrderNumber
        nextOrderNumber += 1
        lastOrderNumber = number

        var orderLines = cart.map {
            OrderLine(name: $0.title, emoji: "", qty: $0.qty, unitWei: String($0.unit), options: $0.detail, isDrink: $0.product.category.isDrink)
        }
        if let c = customAmount { orderLines.append(OrderLine(name: "Custom amount", emoji: "", qty: 1, unitWei: String(c))) }

        // Split total into N parts; the last part absorbs rounding.
        let n = max(1, splitCount)
        let share = total / Wei(n)
        parts = (0..<n).map { i in
            let amt = i == n - 1 ? total - share * Wei(n - 1) : share
            let m = n > 1 ? "Order #\(number) · part \(i + 1)/\(n)" : "#\(number) " + memo
            return PaymentRequest(merchant: payout, amount: amt, memo: m, merchantName: merchantName)
        }
        for (i, r) in parts.enumerated() {
            pendingOrders[r.invoiceId.hex.lowercased()] = (i == 0 ? orderLines : [], i == 0 ? tip : 0, number, n > 1 ? "\(i + 1)/\(n)" : nil, r.amount, nil)
        }
        paidParts = []
        stateMs = [:]
        identifiedPayer = nil
        rewardNotice = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { charge = .awaiting(parts[0]) }
        beacon.publish(parts[0])
        startPolling()
    }

    /// Rehearsal / automation: tapnadpos://charge?items=Espresso,Croissant&split=2
    func handle(url: URL) {
        if url.scheme == "tapnadpos", url.host == "newsale" { newSale(); return }
        if url.scheme == "tapnadpos", url.host == "setup" { setup(from: url); return }
        guard url.scheme == "tapnadpos", url.host == "charge",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        guard charge == .idle else { return }
        clear()
        for name in (q.first { $0.name == "items" }?.value ?? "").split(separator: ",") {
            if let p = catalog.first(where: { $0.name.caseInsensitiveCompare(String(name)) == .orderedSame }) {
                add(p, options: p.category.hasOptions ? DrinkOptions() : nil)
            }
        }
        splitCount = Int(q.first { $0.name == "split" }?.value ?? "") ?? 1
        tipPercent = Int(q.first { $0.name == "tip" }?.value ?? "") ?? 0
        startCharge()
    }

    /// Onboarding from the website: tapnadpos://setup?name=…&payout=0x…&template=cafe|restaurant|retail
    @Published var setupBanner: String?
    func setup(from url: URL) {
        let q = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                           uniquingKeysWith: { a, _ in a })
        if let n = q["name"], !n.isEmpty { merchantName = n }
        if let p = q["payout"], isAddress(p) { payout = p; connect() }
        switch q["template"] {
        case "restaurant": catalog = Product.restaurant
        case "retail": catalog = Product.retail
        case "cafe": catalog = Product.defaults
        default: break
        }
        if charge == .idle { clear() }
        setupBanner = "Welcome, \(merchantName). Your register is ready."
    }

    // MARK: Identify + rewards

    /// A phone tapped and told us its wallet. If it has an unredeemed free drink, comp the cheapest drink
    /// and re-issue the request before the phone reads it.
    func identify(_ payer: String) {
        guard case .awaiting(let req) = charge else { return }
        withAnimation(.snappy) { identifiedPayer = payer }
        guard parts.count == 1, paidParts.isEmpty, let c = customer(payer) else { return }
        let available = c.rewardsEarned - (redeemed[payer.lowercased()] ?? 0)
        guard available > 0, let drink = cart.filter({ $0.product.category.isDrink }).min(by: { $0.unit < $1.unit }) else { return }
        let newAmount = req.amount > drink.unit ? req.amount - drink.unit : 0
        guard newAmount > 0 else { return }
        let key = req.invoiceId.hex.lowercased()
        guard var order = pendingOrders.removeValue(forKey: key) else { return }
        let updated = PaymentRequest(merchant: req.merchant, amount: newAmount, memo: req.memo + ", Reward: free \(drink.title)", merchantName: req.merchantName)
        order.expected = newAmount
        order.reward = "Free \(drink.title)"
        pendingOrders[updated.invoiceId.hex.lowercased()] = order
        parts = [updated]
        rewardNotice = "Free \(drink.title) applied — loyalty reward"
        withAnimation(.snappy) { charge = .awaiting(updated) }
        beacon.publish(updated)
    }

    // MARK: Fallback polling (if the WebSocket feed drops)

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    private func poll() async {
        guard case .awaiting = charge, blockNumber > 0 else { if charge == .idle { stopPolling() }; return }
        let from = Wei(max(0, blockNumber - 40)).hexQuantity
        guard let logs: [[String: Any]] = try? await MonadRPC.shared.call("eth_getLogs", [[
            "address": Chain.monadPay, "fromBlock": from, "toBlock": "latest",
            "topics": [MonadPayABI.paidTopic, MonadPayABI.topic(address: payout)],
        ]]) else { return }
        for var log in logs {
            guard let topics = log["topics"] as? [String], topics.count == 4,
                  !sales.contains(where: { $0.id == topics[2].lowercased() }),
                  pendingOrders[topics[2].lowercased()] != nil else { continue }
            log["commitState"] = CommitState.proposed.rawValue
            onLog(log)
        }
    }

    // MARK: Refunds (sent from the register's refund wallet through MonadPay, so the phone sees them live)

    func refreshRefundBalance() async {
        guard let a = refundAccount else { return }
        refundBalance = try? await MonadRPC.shared.balance(a.address)
    }

    func refund(_ sale: Sale) async -> String? {
        guard let acct = refundAccount, sale.refundTx == nil else { return "No refund wallet" }
        refunding = sale.id
        defer { refunding = nil }
        do {
            let memo = "Refund · Order #\(sale.orderNumber.map(String.init) ?? "—") · \(merchantName)"
            let data = MonadPayABI.encodePay(merchant: sale.event.payer, invoiceId: .random(32), memo: memo)
            async let n = MonadRPC.shared.nonce(acct.address)
            async let gp = MonadRPC.shared.gasPrice()
            async let g = MonadRPC.shared.estimateGas(from: acct.address, to: Chain.monadPay, value: sale.event.amount, data: data)
            let (nonce, price, gas) = try await (n, gp, g)
            let raw = try acct.signLegacy(nonce: nonce, gasPrice: price, gasLimit: gas + gas / 10, to: Chain.monadPay,
                                          value: sale.event.amount, data: data, chainId: Chain.chainId)
            let hash = try await MonadRPC.shared.sendRaw(raw)
            if let i = sales.firstIndex(where: { $0.id == sale.id }) { sales[i].refundTx = hash; saveSales() }
            await refreshRefundBalance()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var refundsTotal: Wei { sales.filter { $0.refundTx != nil }.reduce(0) { $0 + $1.event.amount } }

    var currentPartIndex: Int { paidParts.count }

    func cancelCharge() {
        stopPolling()
        beacon.publish(nil)
        parts = []; paidParts = []
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { charge = .idle }
    }

    func newSale() {
        stopPolling()
        identifiedPayer = nil
        rewardNotice = nil
        beacon.publish(nil)
        parts = []; paidParts = []
        clear()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { charge = .idle }
    }

    private func completeOrder(number: Int, lines: [OrderLine], payer: String) {
        // stock
        for l in lines {
            if let i = catalog.firstIndex(where: { $0.name == l.name }), let s = catalog[i].stock { catalog[i].stock = max(0, s - l.qty) }
        }
        // kitchen
        if !lines.isEmpty {
            tickets.insert(KitchenTicket(number: number, lines: lines, payer: payer, createdAt: Date(), status: .new), at: 0)
            saveTickets()
        }
    }

    func advance(_ t: KitchenTicket) {
        guard let i = tickets.firstIndex(of: t) else { return }
        let all = TicketStatus.allCases
        let next = all[min(all.count - 1, all.firstIndex(of: t.status)! + 1)]
        withAnimation(.snappy) { tickets[i].status = next }
        saveTickets()
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

        var isNew = false
        if let i = sales.firstIndex(where: { $0.id == ev.invoiceId }) {
            for s in CommitState.timeline where s.rank <= state.rank && sales[i].states[s.rawValue] == nil {
                sales[i].states[s.rawValue] = elapsed
            }
        } else {
            isNew = true
            var states: [String: Double] = [:]
            for s in CommitState.timeline where s.rank <= state.rank { states[s.rawValue] = elapsed }
            let order = pendingOrders.removeValue(forKey: ev.invoiceId)
            // Anything paid above the requested amount is a tip the customer added on their phone.
            let phoneTip: Wei = order.map { ev.amount > $0.expected ? ev.amount - $0.expected : 0 } ?? 0
            var sale = Sale(event: ev, date: now, states: states, lines: order?.lines,
                            tipWei: order.map { String($0.tip + phoneTip) }, orderNumber: order?.number, splitPart: order?.part)
            sale.rewardApplied = order?.reward
            if order?.reward != nil { redeemed[ev.payer.lowercased(), default: 0] += 1 }
            withAnimation(.snappy) { sales.insert(sale, at: 0) }
        }
        saveSales()

        // Active charge: advance through split parts, then show approval.
        if isNew, case .awaiting(let req) = charge, req.invoiceId.hex.lowercased() == ev.invoiceId {
            paidParts.append(ev)
            NSSound(named: paidParts.count == parts.count ? "Glass" : "Tink")?.play()
            if paidParts.count < parts.count {
                let next = parts[paidParts.count]
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { charge = .awaiting(next) }
                beacon.publish(next)
            } else {
                beacon.publish(nil)
                stopPolling()
                let firstLines = sales.first { $0.orderNumber == lastOrderNumber && !($0.lines ?? []).isEmpty }?.lines ?? []
                if let n = lastOrderNumber { completeOrder(number: n, lines: firstLines, payer: ev.payer) }
                stateMs = [:]
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { charge = .paid(req, ev) }
            }
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
    var avgTicket: Wei {
        let orders = Set(sales.map { $0.orderNumber.map(String.init) ?? $0.id }).count
        return orders == 0 ? 0 : grossVolume / Wei(orders)
    }
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

    func customer(_ payer: String) -> Customer? { customers.first { $0.address.lowercased() == payer.lowercased() } }

    var topProducts: [(name: String, emoji: String, qty: Int, revenue: Double)] {
        var agg: [String: (Int, Double)] = [:]
        for l in sales.flatMap({ $0.lines ?? [] }) {
            let cur = agg[l.name] ?? (0, 0)
            agg[l.name] = (cur.0 + l.qty, cur.1 + Double(l.unit * Wei(l.qty)) / 1e18)
        }
        return agg.map { ($0.key, "", $0.value.0, $0.value.1) }.sorted { $0.revenue > $1.revenue }
    }

    /// CSV of all transactions.
    func exportCSV() -> String {
        let f = ISO8601DateFormatter()
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "Date,Order,Part,Items,Customer,Amount (USD),Tip (USD),Amount (testnet MON),Status,Finality (ms),Block,Transaction\n"
        for s in sales {
            out += [f.string(from: s.date), s.orderNumber.map(String.init) ?? "", s.splitPart ?? "", esc(s.event.memo), s.event.payer,
                    Money.plain(s.event.amount), Money.plain(s.tip), MON.format(s.event.amount, maxFraction: 18), s.latestState.rawValue,
                    s.finalizedMs.map(String.init) ?? "", String(s.event.blockNumber), s.event.txHash].joined(separator: ",") + "\n"
        }
        return out
    }

    // MARK: Persistence

    private func saveSales() {
        if let d = try? JSONEncoder().encode(Array(sales.prefix(1000))) { UserDefaults.standard.set(d, forKey: "pos.sales") }
    }
    private func saveTickets() {
        if let d = try? JSONEncoder().encode(Array(tickets.prefix(200))) { UserDefaults.standard.set(d, forKey: "pos.tickets") }
    }
    private func saveCatalog() {
        if let d = try? JSONEncoder().encode(catalog) { UserDefaults.standard.set(d, forKey: "pos.catalog") }
    }
    func resetSales() { sales = []; tickets = []; saveSales(); saveTickets() }
}

// MARK: - Refund wallet key
// Stored in a private app file (0600) rather than the Keychain: dev builds are ad-hoc signed, so the
// Keychain re-prompts after every rebuild and would block launch. Testnet funds only.

enum POSKeychain {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TapnadPOS")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("refund.key")
    }

    static func refundAccount() -> EthAccount? {
        if let hex = try? String(contentsOf: url, encoding: .utf8), let d = Data(hex: hex.trimmingCharacters(in: .whitespacesAndNewlines)),
           d.count == 32, let a = try? EthAccount(privateKey: d) {
            return a
        }
        guard let a = try? EthAccount.generate() else { return nil }
        try? a.privateKey.hex.dropFirst(2).write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return a
    }
}
