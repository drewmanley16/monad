import Foundation
import CoreBluetooth
import Network

/// Broadcasts the active charge so a phone can "tap" it, and lets the phone identify itself first.
/// - Bluetooth LE (real iPhone): phone writes its address to `identify`, then reads `request`.
/// - Bonjour (Simulator / same network): TXT advertises the charge; the phone opens a TCP
///   connection, sends `{"payer": "0x…"}\n`, and gets the (possibly reward-adjusted) request back.
final class TapBeacon: NSObject, CBPeripheralManagerDelegate {
    private var peripheral: CBPeripheralManager!
    private var listener: NWListener?
    private(set) var request: PaymentRequest?
    private var serviceAdded = false
    private(set) var bluetoothOn = false
    var name = "Tapnad POS"

    /// Called on the main queue when a phone identifies; return value is ignored —
    /// the store updates the published request synchronously.
    var onIdentify: ((String) -> Void)?

    override init() {
        super.init()
        peripheral = CBPeripheralManager(delegate: self, queue: .main)
        startListener()
    }

    func publish(_ req: PaymentRequest?) {
        request = req
        updateBonjour()
        updateAdvertising()
    }

    // MARK: Bonjour + TCP identify

    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener = l
            updateBonjour()
            l.start(queue: .main)
        } catch {
            print("Bonjour listener failed: \(error)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let payer = obj["payer"], isAddress(payer) {
                self.onIdentify?(payer)
            }
            var reply = self.request?.fields ?? [:]
            reply["state"] = self.request == nil ? "idle" : "charging"
            let body = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
            conn.send(content: body + Data("\n".utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private func updateBonjour() {
        var fields = request?.fields ?? [:]
        fields["state"] = request == nil ? "idle" : "charging"
        listener?.service = NWListener.Service(name: name, type: TapLink.bonjourType, domain: nil, txtRecord: NWTXTRecord(fields).data)
    }

    // MARK: BLE

    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        bluetoothOn = p.state == .poweredOn
        guard bluetoothOn, !serviceAdded else { return }
        let req = CBMutableCharacteristic(type: CBUUID(string: TapLink.requestCharUUID), properties: [.read], value: nil, permissions: [.readable])
        let ident = CBMutableCharacteristic(type: CBUUID(string: TapLink.identifyCharUUID), properties: [.write], value: nil, permissions: [.writeable])
        let s = CBMutableService(type: CBUUID(string: TapLink.serviceUUID), primary: true)
        s.characteristics = [req, ident]
        p.add(s)
    }

    func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        serviceAdded = error == nil
        updateAdvertising()
    }

    private func updateAdvertising() {
        guard bluetoothOn, serviceAdded else { return }
        peripheral.stopAdvertising()
        if request != nil {
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: TapLink.serviceUUID)],
                CBAdvertisementDataLocalNameKey: name,
            ])
        }
    }

    func peripheralManager(_ p: CBPeripheralManager, didReceiveRead req: CBATTRequest) {
        let d = request.map { Data($0.url.absoluteString.utf8) } ?? Data()
        guard req.offset <= d.count else { p.respond(to: req, withResult: .invalidOffset); return }
        req.value = d.subdata(in: req.offset..<d.count)
        p.respond(to: req, withResult: .success)
    }

    func peripheralManager(_ p: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for r in requests where r.characteristic.uuid == CBUUID(string: TapLink.identifyCharUUID) {
            if let v = r.value, let payer = String(data: v, encoding: .utf8), isAddress(payer) { onIdentify?(payer) }
        }
        if let first = requests.first { p.respond(to: first, withResult: .success) }
    }
}
