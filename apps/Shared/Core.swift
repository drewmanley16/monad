import Foundation
import Security

// MARK: - Chain config

enum Chain {
    static let chainId: Swift.UInt128 = 10143
    static let name = "Monad Testnet"
    static let rpc = URL(string: "https://testnet-rpc.monad.xyz")!
    static let ws = URL(string: "wss://testnet-rpc.monad.xyz")!
    static let explorerTx = "https://testnet.monadexplorer.com/tx/"
    static let faucet = URL(string: "https://faucet.monad.xyz")!
    static let site = URL(string: "https://tapnad.vercel.app")!
    /// MonadPay contract on testnet (written by contracts/deploy.sh)
    static let monadPay = "0xF825f70E27b7f65bB44475FB4530b7c09245F128"
}

// MARK: - Hex

extension Data {
    init?(hex: String) {
        var s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        if s.count % 2 == 1 { s = "0" + s }
        var out = Data(capacity: s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self = out
    }
    var hex: String { "0x" + map { String(format: "%02x", $0) }.joined() }

    static func random(_ n: Int) -> Data {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return Data(b)
    }
}

// MARK: - Wei

typealias Wei = Swift.UInt128

extension Swift.UInt128 {
    init?(hexString: String) {
        let s = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        if s.isEmpty { self = 0; return }
        let trimmed = String(s.drop(while: { $0 == "0" }))
        if trimmed.isEmpty { self = 0; return }
        guard trimmed.count <= 32, let v = Swift.UInt128(trimmed, radix: 16) else { return nil }
        self = v
    }
    /// Minimal big-endian bytes (empty for zero), as RLP wants.
    var minimalBytes: Data {
        var v = self
        var out = [UInt8]()
        while v > 0 { out.insert(UInt8(truncatingIfNeeded: v & 0xff), at: 0); v >>= 8 }
        return Data(out)
    }
    var hexQuantity: String { "0x" + String(self, radix: 16) }
}

enum MON {
    static let decimals = 18
    static let one: Wei = 1_000_000_000_000_000_000

    static func parse(_ s: String) -> Wei? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts[0].allSatisfy(\.isNumber),
              let whole = Wei(parts[0].isEmpty ? "0" : String(parts[0])) else { return nil }
        var frac: Wei = 0
        if parts.count == 2 {
            var f = String(parts[1])
            guard f.count <= decimals, f.allSatisfy(\.isNumber) else { return nil }
            f += String(repeating: "0", count: decimals - f.count)
            frac = Wei(f) ?? 0
        }
        return whole * one + frac
    }

    static func format(_ w: Wei, maxFraction: Int = 4) -> String {
        let whole = w / one
        var f = String(w % one)
        f = String(repeating: "0", count: decimals - f.count) + f
        f = String(f.prefix(maxFraction))
        while f.hasSuffix("0") { f.removeLast() }
        return f.isEmpty ? "\(whole)" : "\(whole).\(f)"
    }
}

func shortAddress(_ a: String) -> String { a.count > 12 ? "\(a.prefix(6))…\(a.suffix(4))" : a }
func isAddress(_ a: String) -> Bool { a.hasPrefix("0x") && a.count == 42 && Data(hex: a) != nil }

// MARK: - MonadPay ABI

enum MonadPayABI {
    static let paySelector = Data([0x67, 0x91, 0x01, 0x59])   // pay(address,bytes32,string)
    static let paidTopic = "0xefb6650ea952a1f15b25c0abf0e65623721748fe689043ee32d4e74d79fbc25f"

    static func word(_ d: Data) -> Data { Data(repeating: 0, count: max(0, 32 - d.count)) + d.suffix(32) }

    static func encodePay(merchant: String, invoiceId: Data, memo: String) -> Data {
        let memoBytes = Data(memo.utf8)
        let padded = memoBytes + Data(repeating: 0, count: (32 - memoBytes.count % 32) % 32)
        var out = paySelector
        out += word(Data(hex: merchant) ?? Data())
        out += word(invoiceId)
        out += word(Wei(96).minimalBytes)
        out += word(Wei(memoBytes.count).minimalBytes)
        out += padded
        return out
    }

    static func topic(address: String) -> String { word(Data(hex: address) ?? Data()).hex }
}

/// Decoded `Paid(merchant, invoiceId, payer, amount, memo)` log.
struct PaidEvent: Identifiable, Codable, Hashable {
    var id: String { invoiceId }
    let invoiceId: String
    let payer: String
    let amountWei: String
    let memo: String
    let txHash: String
    let blockNumber: Int
    var amount: Wei { Wei(amountWei) ?? 0 }

    init?(log: [String: Any]) {
        guard let topics = log["topics"] as? [String], topics.count == 4,
              let dataHex = log["data"] as? String, let data = Data(hex: dataHex), data.count >= 96 else { return nil }
        invoiceId = topics[2].lowercased()
        payer = "0x" + topics[3].suffix(40)
        let amt = Wei(hexString: data.subdata(in: 16..<32).hex) ?? 0   // uint256 but fits in 128 bits
        amountWei = String(amt)
        let len = Int(Wei(hexString: data.subdata(in: 64..<96).hex) ?? 0)
        memo = data.count >= 96 + len ? String(decoding: data.subdata(in: 96..<(96 + len)), as: UTF8.self) : ""
        txHash = log["transactionHash"] as? String ?? ""
        blockNumber = Int((log["blockNumber"] as? String).flatMap { Wei(hexString: $0) } ?? 0)
    }
}

// MARK: - Payment request

struct PaymentRequest: Identifiable, Equatable {
    var id: String { invoiceId.hex }
    let merchant: String
    let amount: Wei
    let invoiceId: Data
    let memo: String
    let merchantName: String

    init(merchant: String, amount: Wei, invoiceId: Data = .random(32), memo: String, merchantName: String) {
        self.merchant = merchant; self.amount = amount; self.invoiceId = invoiceId
        self.memo = memo; self.merchantName = merchantName
    }

    /// Short key/value form (fits Bonjour TXT entries, each ≤ 255 bytes).
    var fields: [String: String] {
        ["to": merchant, "amt": MON.format(amount, maxFraction: 18), "inv": invoiceId.hex,
         "name": String(merchantName.prefix(60)), "memo": String(memo.prefix(120))]
    }

    init?(fields q: [String: String]) {
        guard let to = q["to"], isAddress(to), let a = q["amt"], let amt = MON.parse(a), amt > 0,
              let invHex = q["inv"], let inv = Data(hex: invHex), inv.count == 32 else { return nil }
        self.init(merchant: to, amount: amt, invoiceId: inv, memo: q["memo"] ?? "",
                  merchantName: (q["name"] ?? "").isEmpty ? "Merchant" : q["name"]!)
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = "monadpay"; c.host = "pay"
        c.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }

    /// Web checkout link — what the POS QR encodes so any phone camera can pay without the app.
    var webURL: URL {
        var c = URLComponents(url: Chain.site.appendingPathComponent("pay"), resolvingAgainstBaseURL: false)!
        c.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }

    init?(url: URL) {
        let isWeb = url.scheme == "https" && url.host == Chain.site.host && url.path.hasPrefix("/pay")
        guard url.scheme == "monadpay" || isWeb, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        self.init(fields: q)
    }
}

// MARK: - Tap link (POS ⇄ phone discovery)

enum TapLink {
    static let bonjourType = "_tapnad._tcp"
    static let serviceUUID = "6E1A0001-5A1D-4B3C-9E1F-7A9D4D2C0001"
    static let requestCharUUID = "6E1A0002-5A1D-4B3C-9E1F-7A9D4D2C0001"
    /// Phone writes its wallet address here before reading the request (lets the POS apply rewards).
    static let identifyCharUUID = "6E1A0003-5A1D-4B3C-9E1F-7A9D4D2C0001"
    /// RSSI at which a phone counts as "tapped" on the Mac.
    static let tapRSSI = -52
}

// MARK: - JSON-RPC

struct RPCError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class MonadRPC {
    static let shared = MonadRPC()

    func call<T>(_ method: String, _ params: [Any]) async throws -> T {
        var req = URLRequest(url: Chain.rpc)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": Int.random(in: 1...1_000_000), "method": method, "params": params,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError(message: "Bad RPC response")
        }
        if let err = obj["error"] as? [String: Any] {
            throw RPCError(message: (err["message"] as? String ?? "RPC error").capitalizedFirst)
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

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Commit states + WebSocket stream

enum CommitState: String, CaseIterable, Codable {
    case proposed = "Proposed", voted = "Voted", finalized = "Finalized", verified = "Verified"
    var rank: Int { CommitState.allCases.firstIndex(of: self)! }
    static let timeline: [CommitState] = [.proposed, .voted, .finalized]

    var blurb: String {
        switch self {
        case .proposed: "Speculatively executed"
        case .voted: "First-round quorum"
        case .finalized: "Canonical & irreversible"
        case .verified: "State root verified"
        }
    }
}

/// Minimal Monad WebSocket client: `monadNewHeads` / `monadLogs` with auto-reconnect.
final class MonadStream: NSObject {
    struct Sub { let params: [Any]; let handler: ([String: Any]) -> Void }

    private var task: URLSessionWebSocketTask?
    private var subs: [Int: Sub] = [:]
    private var idToSub: [String: Int] = [:]
    private var nextId = 1
    private var stopped = false
    private var pendingAcks: [Int: () -> Void] = [:]
    var onConnectionChange: ((Bool) -> Void)?

    @discardableResult
    func subscribe(_ params: [Any], onAck: (() -> Void)? = nil, handler: @escaping ([String: Any]) -> Void) -> Int {
        let id = nextId; nextId += 1
        subs[id] = Sub(params: params, handler: handler)
        if let onAck { pendingAcks[id] = onAck }
        if task != nil { send(id) }
        return id
    }

    func subscribeAndWait(_ params: [Any], handler: @escaping ([String: Any]) -> Void) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var done = false
            let finish = { if !done { done = true; c.resume() } }
            DispatchQueue.main.async {
                self.subscribe(params, onAck: finish, handler: handler)
                if self.task == nil { self.connect() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: finish)
            }
        }
    }

    func connect() {
        stopped = false
        let t = URLSession.shared.webSocketTask(with: Chain.ws)
        task = t
        idToSub = [:]
        t.resume()
        for id in subs.keys.sorted() { send(id) }
        receive(t)
    }

    func stop() {
        stopped = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func send(_ id: Int) {
        guard let sub = subs[id] else { return }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": "eth_subscribe", "params": sub.params]
        guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
        task?.send(.string(String(decoding: d, as: UTF8.self))) { _ in }
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self, t === self.task else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    self.onConnectionChange?(false)
                    guard !self.stopped else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if !self.stopped { self.connect() } }
                }
            case .success(let msg):
                if case .string(let s) = msg,
                   let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
                    DispatchQueue.main.async { self.handle(obj) }
                }
                self.receive(t)
            }
        }
    }

    private func handle(_ obj: [String: Any]) {
        if let id = obj["id"] as? Int, let subId = obj["result"] as? String {
            idToSub[subId] = id
            onConnectionChange?(true)
            pendingAcks.removeValue(forKey: id)?()
            return
        }
        guard let p = obj["params"] as? [String: Any], let subId = p["subscription"] as? String,
              let res = p["result"] as? [String: Any], let id = idToSub[subId] else { return }
        subs[id]?.handler(res)
    }
}

// MARK: - Money (dollar display; settles in testnet MON underneath)

enum Money {
    /// Fixed display rate for testnet MON, which has no market price.
    static let usdPerMON: Double = 100

    static func usd(_ w: Wei) -> String {
        let dollars = Double(w) / 1e18 * usdPerMON
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    static func dollars(_ w: Wei) -> Double { Double(w) / 1e18 * usdPerMON }

    /// "$3.50" / "3.5" → wei
    static func parse(_ s: String) -> Wei? {
        let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let cents = MON.parse(clean) else { return nil }        // parse as 18-decimal fixed point
        return cents / Wei(usdPerMON)                                  // dollars → MON
    }

    /// Dollar string for a wei amount suitable for a text field ("3.50").
    static func plain(_ w: Wei) -> String { String(format: "%.2f", dollars(w)) }
}
