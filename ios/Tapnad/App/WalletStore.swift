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

/// One step of the live payment timeline.
struct TimelineStep: Identifiable {
    let id: String
    let label: String
    var ms: Int?
}

@MainActor
final class WalletStore: ObservableObject {
    @Published private(set) var account: EthAccount?
    @Published var balance: Wei?
    @Published var history: [PaymentRecord] = []

    // Active payment
    @Published var pending: PaymentRequest?
    @Published var phase: Phase = .idle
    @Published var steps: [TimelineStep] = []
    @Published var lastTxHash: String?

    enum Phase: Equatable { case idle, confirm, authorizing, sending, inFlight, done, failed(String) }

    private var tracker: CommitTracker?
    private var t0 = Date()
    private let historyKey = "tapnad.history"

    init() {
        if let key = Keychain.load(), let acct = try? EthAccount(privateKey: key) {
            account = acct
        } else if let acct = try? EthAccount.generate() {
            Keychain.save(acct.privateKey)
            account = acct
        }
        if let d = UserDefaults.standard.data(forKey: historyKey),
           let h = try? JSONDecoder().decode([PaymentRecord].self, from: d) { history = h }
    }

    var address: String { account?.address ?? "" }

    func refresh() async {
        guard let a = account else { return }
        balance = try? await MonadRPC.shared.balance(a.address)
    }

    func importKey(_ hex: String) -> Bool {
        guard let d = Data(hex: hex.trimmingCharacters(in: .whitespacesAndNewlines)), d.count == 32,
              let acct = try? EthAccount(privateKey: d) else { return false }
        Keychain.save(d)
        account = acct
        balance = nil
        Task { await refresh() }
        return true
    }

    // MARK: Payment flow

    func present(_ req: PaymentRequest) {
        pending = req
        phase = .confirm
        steps = []
        lastTxHash = nil
        Haptics.tap()
    }

    func dismissPayment() {
        tracker?.stop(); tracker = nil
        pending = nil
        phase = .idle
    }

    func pay() async {
        guard let req = pending, let acct = account else { return }
        phase = .authorizing
        guard await Biometrics.authenticate("Pay \(MON.format(req.amount)) MON to \(req.merchantName)") else {
            phase = .confirm; return
        }
        phase = .sending
        do {
            let data = MonadPayABI.encodePay(merchant: req.merchant, invoiceId: req.invoiceId, memo: req.memo)
            async let nonceF = MonadRPC.shared.nonce(acct.address)
            async let priceF = MonadRPC.shared.gasPrice()
            async let gasF = MonadRPC.shared.estimateGas(from: acct.address, to: Chain.monadPay, value: req.amount, data: data)
            let (nonce, price, gasEst) = try await (nonceF, priceF, gasF)
            // Monad charges the full gas limit, so keep the buffer small.
            let gasLimit = gasEst + gasEst / 10

            let raw = try acct.signLegacy(nonce: nonce, gasPrice: price, gasLimit: gasLimit, to: Chain.monadPay,
                                          value: req.amount, data: data, chainId: Chain.chainId)

            // Subscribe BEFORE broadcasting so we never miss the Proposed update.
            steps = [
                .init(id: "signed", label: "Signed on device", ms: nil),
                .init(id: CommitState.proposed.rawValue, label: "Proposed", ms: nil),
                .init(id: CommitState.voted.rawValue, label: "Voted", ms: nil),
                .init(id: CommitState.finalized.rawValue, label: "Finalized", ms: nil),
            ]
            let tracker = CommitTracker { [weak self] state, _ in self?.handle(state) }
            self.tracker = tracker
            await tracker.start(merchant: req.merchant, invoiceId: req.invoiceId)

            t0 = Date()
            mark("signed", 0)
            let hash = try await MonadRPC.shared.sendRaw(raw)
            lastTxHash = hash
            phase = .inFlight
            history.insert(PaymentRecord(txHash: hash, merchantName: req.merchantName, memo: req.memo,
                                         amountWei: String(req.amount), date: Date()), at: 0)
            saveHistory()
            // Safety net: if the socket drops, fall back to "done" after a few seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                if self?.phase == .inFlight { self?.phase = .done; Task { await self?.refresh() } }
            }
        } catch {
            Haptics.error()
            phase = .failed(error.localizedDescription)
        }
    }

    private func handle(_ state: CommitState) {
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        // A block can jump straight to Finalized; fill any earlier steps too.
        for s in CommitState.allCases where s.rank <= state.rank && s != .verified {
            if steps.first(where: { $0.id == s.rawValue })?.ms == nil { mark(s.rawValue, ms) }
        }
        if state == .proposed || (phase == .inFlight && state.rank > 0) {
            if phase != .done { phase = .done; Haptics.success() }
        }
        if let i = history.firstIndex(where: { $0.txHash == lastTxHash }) {
            if state == .proposed || history[i].proposedMs == nil { history[i].proposedMs = history[i].proposedMs ?? ms }
            if state == .finalized { history[i].finalizedMs = ms; saveHistory(); Task { await refresh() } }
        }
    }

    private func mark(_ id: String, _ ms: Int) {
        if let i = steps.firstIndex(where: { $0.id == id }) {
            withAnimation(.spring(duration: 0.35)) { steps[i].ms = ms }
        }
    }

    private func saveHistory() {
        if let d = try? JSONEncoder().encode(Array(history.prefix(50))) {
            UserDefaults.standard.set(d, forKey: historyKey)
        }
    }
}
