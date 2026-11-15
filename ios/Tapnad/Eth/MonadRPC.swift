import Foundation

enum Chain {
    static let chainId: Wei = 10143
    static let rpc = URL(string: "https://testnet-rpc.monad.xyz")!
    static let ws = URL(string: "wss://testnet-rpc.monad.xyz")!
    static let explorerTx = "https://testnet.monadexplorer.com/tx/"
    static let faucet = URL(string: "https://faucet.monad.xyz")!
    /// MonadPay contract on testnet (set by contracts/deploy.sh)
    static let monadPay = "0x0000000000000000000000000000000000000000"
}

struct RPCError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class MonadRPC {
    static let shared = MonadRPC()
    private var nextId = 1

    func call<T>(_ method: String, _ params: [Any]) async throws -> T {
        var req = URLRequest(url: Chain.rpc)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        nextId += 1
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": nextId, "method": method, "params": params,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError(message: "Bad RPC response")
        }
        if let err = obj["error"] as? [String: Any] {
            throw RPCError(message: err["message"] as? String ?? "RPC error")
        }
        guard let result = obj["result"] as? T else { throw RPCError(message: "Unexpected result for \(method)") }
        return result
    }

    func quantity(_ method: String, _ params: [Any]) async throws -> Wei {
        let hex: String = try await call(method, params)
        guard let v = Wei(hexString: hex) else { throw RPCError(message: "Bad quantity") }
        return v
    }

    func balance(_ addr: String) async throws -> Wei { try await quantity("eth_getBalance", [addr, "latest"]) }
    func nonce(_ addr: String) async throws -> Wei { try await quantity("eth_getTransactionCount", [addr, "pending"]) }
    func gasPrice() async throws -> Wei { try await quantity("eth_gasPrice", []) }
    func estimateGas(from: String, to: String, value: Wei, data: Data) async throws -> Wei {
        try await quantity("eth_estimateGas", [["from": from, "to": to, "value": value.hexQuantity, "data": data.hex]])
    }
    func sendRaw(_ raw: Data) async throws -> String { try await call("eth_sendRawTransaction", [raw.hex]) }
}

// MARK: - Live commit-state tracker (monadLogs over WebSocket)

enum CommitState: String, CaseIterable {
    case proposed = "Proposed", voted = "Voted", finalized = "Finalized", verified = "Verified"
    var rank: Int { CommitState.allCases.firstIndex(of: self)! }
}

/// Subscribes to `monadLogs` filtered on a single MonadPay invoice and reports
/// each commit-state transition as it happens.
final class CommitTracker: NSObject {
    private var task: URLSessionWebSocketTask?
    private let onState: (CommitState, String?) -> Void   // state, block number hex
    private var ready: CheckedContinuation<Void, Never>?

    init(onState: @escaping (CommitState, String?) -> Void) { self.onState = onState }

    /// Opens the socket and waits until the subscription is acknowledged.
    func start(merchant: String, invoiceId: Data) async {
        let t = URLSession.shared.webSocketTask(with: Chain.ws)
        task = t
        t.resume()
        let sub: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "eth_subscribe",
            "params": ["monadLogs", [
                "address": Chain.monadPay,
                "topics": [MonadPayABI.paidTopic, MonadPayABI.topic(address: merchant), MonadPayABI.word(invoiceId).hex],
            ]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: sub)
        try? await t.send(.string(String(data: data, encoding: .utf8)!))
        receive()
        await withCheckedContinuation { c in
            ready = c
            // don't hang forever if ack never arrives
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.resumeReady() }
        }
    }

    private func resumeReady() { ready?.resume(); ready = nil }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            if case .success(let msg) = result, case .string(let s) = msg,
               let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
                if obj["id"] as? Int == 1 { DispatchQueue.main.async { self.resumeReady() } }
                if let params = obj["params"] as? [String: Any],
                   let res = params["result"] as? [String: Any],
                   let cs = res["commitState"] as? String, let state = CommitState(rawValue: cs) {
                    let bn = res["blockNumber"] as? String
                    DispatchQueue.main.async { self.onState(state, bn) }
                }
            }
            if case .failure = result { return }
            self.receive()
        }
    }

    func stop() { task?.cancel(with: .goingAway, reason: nil); task = nil }
}
