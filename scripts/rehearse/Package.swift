// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "rehearse", platforms: [.macOS(.v15)],
  dependencies: [.package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.21.1"),
                 .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.4")],
  targets: [.executableTarget(name: "rehearse", dependencies: [.product(name: "P256K", package: "swift-secp256k1"), "CryptoSwift"],
                              swiftSettings: [.swiftLanguageMode(.v5)])])
