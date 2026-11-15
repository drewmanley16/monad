import Foundation
import CryptoSwift
import P256K

extension Data {
    var keccak256: Data { Data(SHA3(variant: .keccak256).calculate(for: Array(self))) }
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
        let lenBytes = Wei(len).minimalBytes
        return Data([offset + 55 + UInt8(lenBytes.count)]) + lenBytes
    }
}

// MARK: - Account

struct EthAccount {
    let privateKey: Data
    let address: String

    init(privateKey: Data) throws {
        self.privateKey = privateKey
        let signing = try P256K.Signing.PrivateKey(dataRepresentation: privateKey, format: .uncompressed)
        let pub = signing.publicKey.dataRepresentation          // 65 bytes, 0x04 prefix
        address = EthAccount.checksum(Data(pub.dropFirst().keccak256.suffix(20)).hex)
    }

    static func generate() throws -> EthAccount { try EthAccount(privateKey: .random(32)) }

    static func checksum(_ addr: String) -> String {
        let lower = addr.lowercased().replacingOccurrences(of: "0x", with: "")
        let hash = Data(lower.utf8).keccak256.hex.dropFirst(2)
        var out = "0x"
        for (c, h) in zip(lower, hash) {
            out.append(Int(String(h), radix: 16)! >= 8 ? Character(c.uppercased()) : c)
        }
        return out
    }

    /// Legacy EIP-155 transaction → raw signed bytes.
    func signLegacy(nonce: Wei, gasPrice: Wei, gasLimit: Wei, to: String, value: Wei, data: Data, chainId: Wei) throws -> Data {
        guard let toBytes = Data(hex: to), toBytes.count == 20 else { throw RPCError(message: "Bad recipient") }
        let base: [RLP.Item] = [
            .bytes(nonce.minimalBytes), .bytes(gasPrice.minimalBytes), .bytes(gasLimit.minimalBytes),
            .bytes(toBytes), .bytes(value.minimalBytes), .bytes(data),
        ]
        let unsigned = RLP.encode(.list(base + [.bytes(chainId.minimalBytes), .bytes(Data()), .bytes(Data())]))

        let key = try P256K.Recovery.PrivateKey(dataRepresentation: privateKey)
        let sig = try key.signature(for: HashDigest(Array(unsigned.keccak256)))
        let compact = try sig.compactRepresentation
        let r = Data(compact.signature.prefix(32).drop(while: { $0 == 0 }))
        let s = Data(compact.signature.suffix(32).drop(while: { $0 == 0 }))
        let v = Wei(compact.recoveryId) + chainId * 2 + 35
        return RLP.encode(.list(base + [.bytes(v.minimalBytes), .bytes(r), .bytes(s)]))
    }
}
