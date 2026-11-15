import Foundation
import Security
import LocalAuthentication
import CoreBluetooth
import Network
import UIKit

// MARK: - Keychain

enum Keychain {
    static let legacyAccount = "tapnad.privatekey"

    static func delete(account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account] as CFDictionary)
    }

    static func save(_ data: Data, account: String = legacyAccount) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String = legacyAccount) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}

enum Biometrics {
    static func authenticate(_ reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true } // simulator
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    static var icon: String {
        let ctx = LAContext(); _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .touchID ? "touchid" : "faceid"
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

// MARK: - Reader discovery (Bluetooth proximity on device, Bonjour in Simulator)

/// Finds a Tapnad POS that is currently charging.
/// - On a real iPhone: BLE scan; fires only when RSSI says the phone is held against the Mac.
/// - In the Simulator (no Bluetooth): Bonjour TXT record on the local network.
final class ReaderScanner: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var proximity: Double = 0        // 0…1, for the "move closer" meter
    @Published var readerName: String?

    private var onFound: ((PaymentRequest) -> Void)?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var browser: NWBrowser?
    private var fired = false

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    func start(_ onFound: @escaping (PaymentRequest) -> Void) {
        stop()
        self.onFound = onFound
        fired = false
        proximity = 0
        readerName = nil
        if ReaderScanner.isSimulator {
            startBonjour()
        } else {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func stop() {
        central?.stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        central = nil
        peripheral = nil
        browser?.cancel()
        browser = nil
    }

    private func deliver(_ req: PaymentRequest) {
        guard !fired else { return }
        fired = true
        DispatchQueue.main.async {
            self.stop()
            self.onFound?(req)
        }
    }

    // MARK: Bonjour

    private func startBonjour() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: TapLink.bonjourType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                guard case .bonjour(let txt) = r.metadata else { continue }
                var dict: [String: String] = [:]
                for (k, v) in txt.dictionary { dict[k] = v }
                guard dict["state"] == "charging", let req = PaymentRequest(fields: dict) else { continue }
                DispatchQueue.main.async {
                    self?.readerName = req.merchantName
                    withAnimation { self?.proximity = 1 }
                }
                // tiny delay so the "found" state is visible
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.deliver(req) }
                return
            }
        }
        b.start(queue: .main)
        browser = b
    }

    // MARK: BLE

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [CBUUID(string: TapLink.serviceUUID)],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi != 127, peripheral.state == .disconnected, self.peripheral == nil || self.peripheral == peripheral else { return }
        // map -90…TapLink.tapRSSI dBm → 0…1
        let p = min(1, max(0, Double(rssi + 90) / Double(TapLink.tapRSSI + 90)))
        withAnimation(.easeOut(duration: 0.25)) { proximity = max(proximity * 0.6, p) }
        readerName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if rssi >= TapLink.tapRSSI {
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
            Haptics.soft()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: TapLink.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        centralManagerDidUpdateState(central)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first else { return }
        peripheral.discoverCharacteristics([CBUUID(string: TapLink.requestCharUUID)], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let c = service.characteristics?.first else { return }
        peripheral.readValue(for: c)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let d = characteristic.value, let url = URL(string: String(decoding: d, as: UTF8.self)),
              let req = PaymentRequest(url: url) else {
            // POS not charging (empty value) — resume scanning
            central?.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
            if let c = central { centralManagerDidUpdateState(c) }
            return
        }
        deliver(req)
    }
}

import SwiftUI
