import Foundation
import CryptoSwift
import P256K

// MARK: - Hex helpers

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
    var keccak256: Data { Data(SHA3(variant: .keccak256).calculate(for: Array(self))) }
}

// MARK: - Wei math (Swift.UInt128 is plenty for balances/fees)

typealias Wei = Swift.UInt128

extension Swift.UInt128 {
    init?(hexString: String) {
        let s = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        if s.isEmpty { self = 0; return }
        guard s.count <= 32, let v = Swift.UInt128(s, radix: 16) else { return nil }
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

    /// "1.25" -> wei
    static func parse(_ s: String) -> Wei? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = Wei(parts[0].isEmpty ? "0" : String(parts[0])) else { return nil }
        var frac: Wei = 0
        if parts.count == 2 {
            var f = String(parts[1])
            guard f.count <= decimals, f.allSatisfy(\.isNumber) else { return nil }
            f += String(repeating: "0", count: decimals - f.count)
            frac = Wei(f) ?? 0
        }
        return whole * one + frac
    }

    /// wei -> "1.25"
    static func format(_ w: Wei, maxFraction: Int = 4) -> String {
        let whole = w / one
        let frac = w % one
        var f = String(frac)
        f = String(repeating: "0", count: decimals - f.count) + f
        f = String(f.prefix(maxFraction))
        while f.hasSuffix("0") { f.removeLast() }
        return f.isEmpty ? "\(whole)" : "\(whole).\(f)"
    }
}

// MARK: - RLP

enum RLP {
    indirect enum Item { case bytes(Data), list([Item]) }

    static func encode(_ item: Item) -> Data {
        switch item {
        case .bytes(let d):
            if d.count == 1, d[d.startIndex] < 0x80 { return d }
            return header(d.count, offset: 0x80) + d
        case .list(let items):
            let body = items.reduce(Data()) { $0 + encode($1) }
            return header(body.count, offset: 0xc0) + body
        }
    }

    private static func header(_ len: Int, offset: UInt8) -> Data {
        if len < 56 { return Data([offset + UInt8(len)]) }
        let lenBytes = Swift.UInt128(len).minimalBytes
        return Data([offset + 55 + UInt8(lenBytes.count)]) + lenBytes
    }
}

// MARK: - Account

struct EthAccount {
    let privateKey: Data
    let address: String  // checksummed

    init(privateKey: Data) throws {
        self.privateKey = privateKey
        let signing = try P256K.Signing.PrivateKey(dataRepresentation: privateKey, format: .uncompressed)
        let pub = signing.publicKey.dataRepresentation  // 65 bytes, 0x04 prefix
        let addrBytes = pub.dropFirst().keccak256.suffix(20)
        self.address = EthAccount.checksum(Data(addrBytes).hex)
    }

    static func generate() throws -> EthAccount {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &bytes) == errSecSuccess else {
            throw NSError(domain: "Tapnad", code: 1, userInfo: [NSLocalizedDescriptionKey: "RNG failed"])
        }
        return try EthAccount(privateKey: Data(bytes))
    }

    static func checksum(_ addr: String) -> String {
        let lower = addr.lowercased().replacingOccurrences(of: "0x", with: "")
        let hash = Data(lower.utf8).keccak256.hex.dropFirst(2)
        var out = "0x"
        for (c, h) in zip(lower, hash) {
            out.append(Int(String(h), radix: 16)! >= 8 ? Character(c.uppercased()) : c)
        }
        return out
    }

    static func isValid(_ addr: String) -> Bool {
        addr.hasPrefix("0x") && addr.count == 42 && Data(hex: addr) != nil
    }

    /// Sign a legacy EIP-155 transaction; returns raw tx bytes.
    func signLegacy(nonce: Swift.UInt128, gasPrice: Wei, gasLimit: Swift.UInt128, to: String,
                    value: Wei, data: Data, chainId: Swift.UInt128) throws -> Data {
        guard let toBytes = Data(hex: to), toBytes.count == 20 else {
            throw NSError(domain: "Tapnad", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad recipient"])
        }
        let base: [RLP.Item] = [
            .bytes(nonce.minimalBytes), .bytes(gasPrice.minimalBytes), .bytes(gasLimit.minimalBytes),
            .bytes(toBytes), .bytes(value.minimalBytes), .bytes(data),
        ]
        let unsigned = RLP.encode(.list(base + [.bytes(chainId.minimalBytes), .bytes(Data()), .bytes(Data())]))
        let digest = Array(unsigned.keccak256)

        let key = try P256K.Recovery.PrivateKey(dataRepresentation: privateKey)
        let sig = try key.signature(for: HashDigest(digest))
        let compact = try sig.compactRepresentation
        let rs = compact.signature
        let r = UInt128Strip(rs.prefix(32))
        let s = UInt128Strip(rs.suffix(32))
        let v = Swift.UInt128(compact.recoveryId) + chainId * 2 + 35

        return RLP.encode(.list(base + [.bytes(v.minimalBytes), .bytes(r), .bytes(s)]))
    }
}

/// Strip leading zero bytes (r/s are 256-bit so we can't use Swift.UInt128).
private func UInt128Strip(_ d: Data) -> Data {
    Data(d.drop(while: { $0 == 0 }))
}

// MARK: - ABI for MonadPay.pay(address,bytes32,string)

enum MonadPayABI {
    static let paySelector = Data([0x67, 0x91, 0x01, 0x59])
    static let paidTopic = "0xefb6650ea952a1f15b25c0abf0e65623721748fe689043ee32d4e74d79fbc25f"

    static func word(_ d: Data) -> Data { Data(repeating: 0, count: max(0, 32 - d.count)) + d }

    static func encodePay(merchant: String, invoiceId: Data, memo: String) -> Data {
        let memoBytes = Data(memo.utf8)
        let padded = memoBytes + Data(repeating: 0, count: (32 - memoBytes.count % 32) % 32)
        var out = paySelector
        out += word(Data(hex: merchant) ?? Data())
        out += word(invoiceId)
        out += word(Swift.UInt128(96).minimalBytes)      // offset of string
        out += word(Swift.UInt128(memoBytes.count).minimalBytes)
        out += padded
        return out
    }

    static func topic(address: String) -> String { word(Data(hex: address) ?? Data()).hex }
}
