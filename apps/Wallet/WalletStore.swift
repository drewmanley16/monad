import Foundation
import SwiftUI

struct PaymentRecord: Codable, Identifiable {
    var id: String { txHash }
    let txHash: String
    let merchantName: String
    let memo: String
    let amountWei: String
    let date: Date
    var proposedMs: Int?
    var finalizedMs: Int?
    var amount: Wei { Wei(amountWei) ?? 0 }
}

@MainActor
final class WalletStore: ObservableObject {
    @Published private(set) var account: EthAccount?
    @Published var balance: Wei?
    @Published var history: [PaymentRecord] = []

    // Active payment
    @Published var request: PaymentRequest?
    @Published var phase: Phase = .scanning
    @Published var stateMs: [CommitState: Int] = [:]
    @Published var signedMs: Int?
    @Published var txHash: String?

    enum Phase: Equatable { case scanning, confirm, authorizing, sending, approved, failed(String) }

    private var stream: MonadStream?
    private var t0 = Date()
    private let historyKey = "tapnad.history"

    init() {
        if let key = Keychain.load(), let acct = try? EthAccount(privateKey: key) {
            account = acct
        } else if let acct = try? EthAccount.generate() {
            Keychain.save(acct.privateKey)
            account = acct
        }
        // Public address mirrored to defaults so tooling (simctl) can fund the wallet.
        UserDefaults.standard.set(account?.address, forKey: "tapnad.address")
        if let d = UserDefaults.standard.data(forKey: historyKey),
           let h = try? JSONDecoder().decode([PaymentRecord].self, from: d) { history = h }
    }

    var address: String { account?.address ?? "" }

    func refresh() async {
        guard let a = account else { return }
        if let b = try? await MonadRPC.shared.balance(a.address) {
            withAnimation(.snappy) { balance = b }
        }
    }

    func importKey(_ hex: String) -> Bool {
        guard let d = Data(hex: hex.trimmingCharacters(in: .whitespacesAndNewlines)), d.count == 32,
              let acct = try? EthAccount(privateKey: d) else { return false }
        Keychain.save(d)
        account = acct
        UserDefaults.standard.set(acct.address, forKey: "tapnad.address")
        balance = nil
        Task { await refresh() }
        return true
    }

    // MARK: Payment flow

    func beginTap() {
        stream?.stop(); stream = nil
        request = nil
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

    var insufficient: Bool {
        guard let r = request, let b = balance else { return false }
        return b < r.amount
    }

    func pay() async {
        guard let req = request, let acct = account else { return }
        phase = .authorizing
        guard await Biometrics.authenticate("Pay \(MON.format(req.amount)) MON to \(req.merchantName)") else {
            phase = .confirm; return
        }
        withAnimation { phase = .sending }
        do {
            let data = MonadPayABI.encodePay(merchant: req.merchant, invoiceId: req.invoiceId, memo: req.memo)
            async let nonceF = MonadRPC.shared.nonce(acct.address)
            async let priceF = MonadRPC.shared.gasPrice()
            async let gasF = MonadRPC.shared.estimateGas(from: acct.address, to: Chain.monadPay, value: req.amount, data: data)
            async let subF: Void = subscribe(req)
            let (nonce, price, gasEst, _) = try await (nonceF, priceF, gasF, subF)
            // Monad charges the full gas limit — keep the buffer small.
            let gasLimit = gasEst + gasEst / 10
            let raw = try acct.signLegacy(nonce: nonce, gasPrice: price, gasLimit: gasLimit, to: Chain.monadPay,
                                          value: req.amount, data: data, chainId: Chain.chainId)
            t0 = Date()
            signedMs = 0
            let hash = try await MonadRPC.shared.sendRaw(raw)
            txHash = hash
            history.insert(PaymentRecord(txHash: hash, merchantName: req.merchantName, memo: req.memo,
                                         amountWei: String(req.amount), date: Date()), at: 0)
            saveHistory()
            // Safety net if the socket misses the update.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.phase == .sending, self.txHash == hash else { return }
                withAnimation { self.phase = .approved }
            }
        } catch {
            Haptics.error()
            withAnimation { phase = .failed(error.localizedDescription) }
        }
    }

    /// Subscribe to this invoice's `Paid` log BEFORE broadcasting so the Proposed update can't be missed.
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
            if history[i].proposedMs == nil { history[i].proposedMs = stateMs[.proposed] }
            if state.rank >= CommitState.finalized.rank { history[i].finalizedMs = stateMs[.finalized]; saveHistory() }
        }
    }

    private func saveHistory() {
        if let d = try? JSONEncoder().encode(Array(history.prefix(50))) {
            UserDefaults.standard.set(d, forKey: historyKey)
        }
    }
}
