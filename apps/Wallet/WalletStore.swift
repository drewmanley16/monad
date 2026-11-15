import Foundation
import SwiftUI

@MainActor
final class WalletStore: ObservableObject {
    // Cards
    @Published private(set) var cards: [CardAccount] = []
    @Published var selectedCardId: UUID? { didSet { save() } }
    @Published var balances: [UUID: Wei] = [:]

    // Ledger + budgets
    @Published var history: [PaymentRecord] = []
    @Published var budgets: [ExpenseCategory: Double] = [:] { didSet { save() } }   // dollars per month

    // Active payment
    @Published var request: PaymentRequest?
    @Published var phase: Phase = .scanning
    @Published var stateMs: [CommitState: Int] = [:]
    @Published var signedMs: Int?
    @Published var txHash: String?
    @Published var tipPercent = 0

    private var incoming: MonadStream?

    enum Phase: Equatable { case scanning, confirm, authorizing, sending, approved, failed(String) }

    private var accounts: [UUID: EthAccount] = [:]
    private var stream: MonadStream?
    private var t0 = Date()
    private let defaults = UserDefaults.standard

    init() {
        load()
        if cards.isEmpty {
            // migrate the v1 single key, or create a fresh card
            if let legacy = Keychain.load(), let acct = try? EthAccount(privateKey: legacy) {
                addCard(acct, name: "Personal", theme: .monad, business: false)
            } else {
                _ = createCard(name: "Personal", theme: .monad, business: false)
            }
        }
        for c in cards {
            if let k = Keychain.load(account: Self.keyName(c.id)), let a = try? EthAccount(privateKey: k) { accounts[c.id] = a }
        }
        if selectedCardId == nil || !cards.contains(where: { $0.id == selectedCardId }) { selectedCardId = cards.first?.id }
        defaults.set(cards.first?.address, forKey: "tapnad.address")   // for tooling (simctl funding)
        listenForIncoming()
    }

    // MARK: Cards

    var selectedCard: CardAccount? { cards.first { $0.id == selectedCardId } ?? cards.first }
    var address: String { selectedCard?.address ?? "" }
    var balance: Wei? { selectedCard.flatMap { balances[$0.id] } }
    var totalBalance: Wei { cards.reduce(0) { $0 + (balances[$1.id] ?? 0) } }

    private static func keyName(_ id: UUID) -> String { "tapnad.key.\(id.uuidString)" }

    @discardableResult
    func createCard(name: String, theme: CardTheme, business: Bool) -> CardAccount? {
        guard let acct = try? EthAccount.generate() else { return nil }
        return addCard(acct, name: name, theme: theme, business: business)
    }

    @discardableResult
    private func addCard(_ acct: EthAccount, name: String, theme: CardTheme, business: Bool) -> CardAccount {
        let card = CardAccount(id: UUID(), name: name, theme: theme, isBusiness: business, address: acct.address)
        Keychain.save(acct.privateKey, account: Self.keyName(card.id))
        accounts[card.id] = acct
        withAnimation(.snappy) { cards.append(card) }
        save()
        listenForIncoming()
        Task { await refresh() }
        return card
    }

    func importCard(hex: String, name: String, theme: CardTheme, business: Bool) -> Bool {
        guard let d = Data(hex: hex.trimmingCharacters(in: .whitespacesAndNewlines)), d.count == 32,
              let acct = try? EthAccount(privateKey: d) else { return false }
        let c = addCard(acct, name: name, theme: theme, business: business)
        selectedCardId = c.id
        return true
    }

    func update(_ card: CardAccount) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card; save() }
    }

    func delete(_ card: CardAccount) {
        guard cards.count > 1 else { return }
        withAnimation(.snappy) { cards.removeAll { $0.id == card.id } }
        Keychain.delete(account: Self.keyName(card.id))
        accounts[card.id] = nil
        if selectedCardId == card.id { selectedCardId = cards.first?.id }
        save()
    }

    /// Free test money from the Tapnad faucet (server sends a small amount of testnet MON).
    func requestTestMoney() async -> String? {
        guard let addr = selectedCard?.address else { return "No card" }
        var req = URLRequest(url: Chain.site.appendingPathComponent("api/faucet"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["address": addr])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if (resp as? HTTPURLResponse)?.statusCode != 200 { return obj?["error"] as? String ?? "Couldn't add money" }
            try? await Task.sleep(for: .seconds(3))   // let the funds become spendable
            await refresh()
            return nil
        } catch { return error.localizedDescription }
    }

    func privateKeyHex(_ card: CardAccount) -> String? { Keychain.load(account: Self.keyName(card.id))?.hex }

    func refresh() async {
        await withTaskGroup(of: (UUID, Wei?).self) { g in
            for c in cards { g.addTask { (c.id, try? await MonadRPC.shared.balance(c.address)) } }
            for await (id, b) in g { if let b { withAnimation(.snappy) { balances[id] = b } } }
        }
    }

    // MARK: Incoming (refunds sent to any of our cards via MonadPay)

    func listenForIncoming() {
        incoming?.stop()
        let s = MonadStream()
        incoming = s
        for card in cards {
            s.subscribe(["monadLogs", ["address": Chain.monadPay, "topics": [MonadPayABI.paidTopic, MonadPayABI.topic(address: card.address)]]]) { [weak self] log in
                guard let self, let ev = PaidEvent(log: log), !self.history.contains(where: { $0.txHash == ev.txHash }) else { return }
                var rec = PaymentRecord(txHash: ev.txHash, merchantName: ev.memo.hasPrefix("Refund") ? "Refund" : "Received",
                                        merchant: ev.payer, memo: ev.memo, amountWei: ev.amountWei, date: Date())
                rec.cardId = card.id
                rec.incoming = true
                rec.category = .other
                withAnimation(.snappy) { self.history.insert(rec, at: 0) }
                Haptics.success()
                self.save()
                Task { await self.refresh() }
            }
        }
        s.connect()
    }

    // MARK: Ledger

    func card(for rec: PaymentRecord) -> CardAccount? { cards.first { $0.id == rec.cardId } }

    func setCategory(_ cat: ExpenseCategory, for rec: PaymentRecord) { mutate(rec) { $0.category = cat } }
    func setNote(_ note: String, for rec: PaymentRecord) { mutate(rec) { $0.note = note.isEmpty ? nil : note } }

    private func mutate(_ rec: PaymentRecord, _ f: (inout PaymentRecord) -> Void) {
        guard let i = history.firstIndex(where: { $0.id == rec.id }) else { return }
        f(&history[i]); save()
    }

    func records(inMonthOf date: Date = .now) -> [PaymentRecord] {
        let cal = Calendar.current
        return history.filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    func spend(_ recs: [PaymentRecord]) -> Double {
        recs.reduce(0) { $0 + (($1.incoming ?? false) ? -Money.dollars($1.amount) : Money.dollars($1.amount)) }
    }

    /// CSV for expense reports.
    func exportCSV(_ recs: [PaymentRecord]) -> URL {
        var csv = "Date,Merchant,Items,Category,Card,Type,Amount (USD),Network fee (USD),Note,Transaction\n"
        let f = ISO8601DateFormatter()
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        for r in recs {
            let card = card(for: r)
            csv += [f.string(from: r.date), esc(r.merchantName), esc(r.memo), esc(r.resolvedCategory.name),
                    esc(card?.name ?? "—"), (card?.isBusiness ?? false) ? "Business" : "Personal",
                    Money.plain(r.amount), Money.plain(r.fee),
                    esc(r.note ?? ""), r.txHash].joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tapnad-Expenses-\(Date.now.formatted(.iso8601.year().month())).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Payment flow

    func beginTap() {
        stream?.stop(); stream = nil
        request = nil
        tipPercent = 0
        phase = .scanning
        stateMs = [:]
        signedMs = nil
        txHash = nil
    }

    func found(_ req: PaymentRequest) {
        request = req
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .confirm }
        Haptics.tap()
    }

    func endPayment() {
        stream?.stop(); stream = nil
        Task { await refresh() }
    }

    /// Request amount plus any tip the customer chose on the phone.
    var payAmount: Wei {
        guard let r = request else { return 0 }
        return r.amount + r.amount * Wei(tipPercent) / 100
    }

    var insufficient: Bool {
        guard request != nil, let b = balance else { return false }
        return b < payAmount
    }

    func pay() async {
        guard let req = request, let card = selectedCard, let acct = accounts[card.id] else { return }
        phase = .authorizing
        let amount = payAmount
        guard await Biometrics.authenticate("Pay \(Money.usd(amount)) to \(req.merchantName)") else {
            phase = .confirm; return
        }
        withAnimation { phase = .sending }
        do {
            let data = MonadPayABI.encodePay(merchant: req.merchant, invoiceId: req.invoiceId, memo: req.memo)
            async let nonceF = MonadRPC.shared.nonce(acct.address)
            async let priceF = MonadRPC.shared.gasPrice()
            async let gasF = MonadRPC.shared.estimateGas(from: acct.address, to: Chain.monadPay, value: amount, data: data)
            async let subF: Void = subscribe(req)
            let (nonce, price, gasEst, _) = try await (nonceF, priceF, gasF, subF)
            let gasLimit = gasEst + gasEst / 10          // Monad charges the full gas limit
            let raw = try acct.signLegacy(nonce: nonce, gasPrice: price, gasLimit: gasLimit, to: Chain.monadPay,
                                          value: amount, data: data, chainId: Chain.chainId)
            t0 = Date()
            signedMs = 0
            var hash = ""
            for attempt in 0..<5 {
                do { hash = try await MonadRPC.shared.sendRaw(raw); break }
                catch let e as RPCError where attempt < 4 && e.message.localizedCaseInsensitiveContains("insufficient balance") {
                    try? await Task.sleep(for: .seconds(1))   // freshly received funds settle in ~1–2 s
                }
            }
            txHash = hash
            var rec = PaymentRecord(txHash: hash, merchantName: req.merchantName, merchant: req.merchant, memo: req.memo,
                                    amountWei: String(amount), date: Date())
            rec.cardId = card.id
            rec.feeWei = String(gasLimit * price)
            rec.proposedMs = stateMs[.proposed]
            history.insert(rec, at: 0)
            save()
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.phase == .sending, self.txHash == hash else { return }
                withAnimation { self.phase = .approved }
            }
        } catch {
            Haptics.error()
            withAnimation { phase = .failed(error.localizedDescription) }
        }
    }

    private func subscribe(_ req: PaymentRequest) async {
        let s = MonadStream()
        stream = s
        await s.subscribeAndWait(["monadLogs", [
            "address": Chain.monadPay,
            "topics": [MonadPayABI.paidTopic, MonadPayABI.topic(address: req.merchant), MonadPayABI.word(req.invoiceId).hex],
        ]]) { [weak self] log in
            guard let cs = log["commitState"] as? String, let state = CommitState(rawValue: cs) else { return }
            self?.handle(state)
        }
    }

    private func handle(_ state: CommitState) {
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        for s in CommitState.timeline where s.rank <= state.rank && stateMs[s] == nil {
            withAnimation(.spring(duration: 0.35)) { stateMs[s] = ms }
        }
        if phase == .sending {
            Haptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { phase = .approved }
        }
        if let i = history.firstIndex(where: { $0.txHash == txHash }) {
            history[i].proposedMs = history[i].proposedMs ?? stateMs[.proposed]
            history[i].votedMs = history[i].votedMs ?? stateMs[.voted]
            history[i].finalizedMs = history[i].finalizedMs ?? stateMs[.finalized]
            save()
        }
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var cards: [CardAccount]
        var selected: UUID?
        var budgets: [String: Double]
    }

    private func save() {
        let s = Saved(cards: cards, selected: selectedCardId,
                      budgets: Dictionary(uniqueKeysWithValues: budgets.map { ($0.key.rawValue, $0.value) }))
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: "tapnad.state") }
        if let d = try? JSONEncoder().encode(Array(history.prefix(500))) { defaults.set(d, forKey: "tapnad.history") }
    }

    private func load() {
        if let d = defaults.data(forKey: "tapnad.state"), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            cards = s.cards
            selectedCardId = s.selected
            budgets = Dictionary(uniqueKeysWithValues: s.budgets.compactMap { k, v in ExpenseCategory(rawValue: k).map { ($0, v) } })
        }
        if let d = defaults.data(forKey: "tapnad.history"), let h = try? JSONDecoder().decode([PaymentRecord].self, from: d) {
            history = h
            // attach v1 history to the first card
            if let first = cards.first?.id { for i in history.indices where history[i].cardId == nil { history[i].cardId = first } }
        }
    }
}
