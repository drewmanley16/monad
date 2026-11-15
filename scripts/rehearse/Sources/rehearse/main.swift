// Rehearsal: drives the real POS end-to-end, the same way the iOS Simulator wallet does.
//   swift run rehearse "Oat Latte,Croissant" [split] [tip%]
import Foundation
import Network

let args = CommandLine.arguments
let items = args.count > 1 ? args[1] : "Oat Latte,Croissant"
let split = args.count > 2 ? Int(args[2]) ?? 1 : 1
let phoneTip = args.count > 3 ? Int(args[3]) ?? 0 : 0

guard let keyHex = ProcessInfo.processInfo.environment["PRIVATE_KEY"], let key = Data(hex: keyHex),
      let payer = try? EthAccount(privateKey: key) else { print("set PRIVATE_KEY"); exit(1) }
print("payer \(payer.address)")

// 1. reset, then start a charge on the POS
func openURL(_ u: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = [u]; try? p.run(); p.waitUntilExit() }
openURL("tapnadpos://newsale"); Thread.sleep(forTimeInterval: 0.8)
let q = items.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["tapnadpos://charge?items=\(q)&split=\(split)"]
try p.run(); p.waitUntilExit()

// 2. discover + identify over Bonjour/TCP, like the simulator wallet
func nextRequest(skip: Set<String>) async -> PaymentRequest {
    await withCheckedContinuation { (c: CheckedContinuation<PaymentRequest, Never>) in
        var done = false
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: TapLink.bonjourType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { results, _ in
            for r in results {
                guard !done, case .bonjour(let txt) = r.metadata, txt.dictionary["state"] == "charging",
                      let inv = txt.dictionary["inv"], !skip.contains(inv) else { continue }
                done = true
                let conn = NWConnection(to: r.endpoint, using: .tcp)
                conn.stateUpdateHandler = { s in
                    guard case .ready = s else { return }
                    conn.send(content: try! JSONSerialization.data(withJSONObject: ["payer": payer.address]), completion: .contentProcessed { _ in
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                            let obj = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: String] ?? [:]
                            b.cancel(); conn.cancel()
                            c.resume(returning: PaymentRequest(fields: obj)!)
                        }
                    })
                }
                conn.start(queue: .main)
            }
        }
        b.start(queue: .main)
    }
}

func pay(_ req: PaymentRequest) async throws {
    let amount = req.amount + req.amount * Wei(phoneTip) / 100
    let data = MonadPayABI.encodePay(merchant: req.merchant, invoiceId: req.invoiceId, memo: req.memo)
    let nonce = try await MonadRPC.shared.nonce(payer.address)
    let price = try await MonadRPC.shared.gasPrice()
    let gas = try await MonadRPC.shared.estimateGas(from: payer.address, to: Chain.monadPay, value: amount, data: data)
    let raw = try payer.signLegacy(nonce: nonce, gasPrice: price, gasLimit: gas + gas / 10, to: Chain.monadPay, value: amount, data: data, chainId: Chain.chainId)
    var t0 = Date()
    let s = MonadStream()
    await s.subscribeAndWait(["monadLogs", ["address": Chain.monadPay, "topics": [MonadPayABI.paidTopic, MonadPayABI.topic(address: req.merchant), MonadPayABI.word(req.invoiceId).hex]]]) { log in
        print("   \(log["commitState"] ?? "?") +\(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    }
    t0 = Date()
    print("   tx \(try await MonadRPC.shared.sendRaw(raw))")
    try await Task.sleep(for: .seconds(2.5))
    s.stop()
}

var seen = Set<String>()
for i in 0..<split {
    let req = await nextRequest(skip: seen)
    seen.insert(req.invoiceId.hex)
    if ProcessInfo.processInfo.environment["PRINT_URL"] != nil { print(req.webURL.absoluteString); exit(0) }
    print("part \(i + 1)/\(split): \(MON.format(req.amount, maxFraction: 6)) MON  memo=\"\(req.memo)\"")
    try await pay(req)
}
print("done — check the POS approval screen")
