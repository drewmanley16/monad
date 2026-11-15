import Foundation
import Security
import LocalAuthentication
import CoreNFC
import UIKit

// MARK: - Keychain

enum Keychain {
    private static let account = "tapnad.privatekey"

    static func save(_ data: Data) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}

// MARK: - Biometrics

enum Biometrics {
    static func authenticate(_ reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true } // simulator
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

// MARK: - Payment request  (monadpay://pay?to=..&amount=..&invoice=..&memo=..&name=..)

struct PaymentRequest: Identifiable, Equatable {
    var id: String { invoiceId.hex }
    let merchant: String
    let amount: Wei
    let invoiceId: Data
    let memo: String
    let merchantName: String

    init(merchant: String, amount: Wei, invoiceId: Data, memo: String, merchantName: String) {
        self.merchant = merchant; self.amount = amount; self.invoiceId = invoiceId
        self.memo = memo; self.merchantName = merchantName
    }

    init?(url: URL) {
        guard url.scheme == "monadpay",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let q = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let to = q["to"], EthAccount.isValid(to),
              let amtStr = q["amount"], let amt = MON.parse(amtStr), amt > 0 else { return nil }
        merchant = to
        amount = amt
        if let inv = q["invoice"], let d = Data(hex: inv), d.count <= 32, !d.isEmpty {
            invoiceId = Data(repeating: 0, count: 32 - d.count) + d
        } else {
            var b = [UInt8](repeating: 0, count: 32); _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
            invoiceId = Data(b)
        }
        memo = q["memo"] ?? ""
        merchantName = q["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "Merchant"
    }

    /// Static tags reuse their invoice forever; give each tap a fresh one so receipts stay unique.
    func freshInvoiceIfStatic(fromTag: Bool) -> PaymentRequest {
        guard fromTag else { return self }
        var b = [UInt8](repeating: 0, count: 32); _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
        return PaymentRequest(merchant: merchant, amount: amount, invoiceId: Data(b), memo: memo, merchantName: merchantName)
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = "monadpay"; c.host = "pay"
        c.queryItems = [
            .init(name: "to", value: merchant), .init(name: "amount", value: MON.format(amount, maxFraction: 18)),
            .init(name: "name", value: merchantName), .init(name: "memo", value: memo),
        ]
        return c.url!
    }
}

// MARK: - NFC

final class NFCReader: NSObject, NFCNDEFReaderSessionDelegate {
    private var session: NFCNDEFReaderSession?
    private var completion: ((URL?) -> Void)?
    private var writeURL: URL?

    static var available: Bool { NFCNDEFReaderSession.readingAvailable }

    func read(_ completion: @escaping (URL?) -> Void) {
        self.completion = completion
        writeURL = nil
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near the Tapnad reader."
        session?.begin()
    }

    func write(_ url: URL, _ completion: @escaping (URL?) -> Void) {
        self.completion = completion
        writeURL = url
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near a blank NFC tag."
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] err in
            guard let self else { return }
            if err != nil { session.invalidate(errorMessage: "Couldn't connect. Try again."); return }
            if let url = self.writeURL {
                guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else { return }
                tag.writeNDEF(NFCNDEFMessage(records: [payload])) { e in
                    if let e { session.invalidate(errorMessage: e.localizedDescription) }
                    else { session.alertMessage = "Reader programmed ✓"; session.invalidate(); self.finish(url) }
                }
            } else {
                tag.readNDEF { msg, _ in
                    let url = msg?.records.compactMap { $0.wellKnownTypeURIPayload() }.first
                    if let url, PaymentRequest(url: url) != nil {
                        session.alertMessage = "Reader found"
                        session.invalidate()
                        self.finish(url)
                    } else {
                        session.invalidate(errorMessage: "Not a Tapnad reader.")
                    }
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        finish(nil)
    }

    private func finish(_ url: URL?) {
        let c = completion; completion = nil
        DispatchQueue.main.async { c?(url) }
    }
}

// MARK: - Haptics

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
}
