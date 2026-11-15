import Foundation
import CoreBluetooth
import Network

/// Broadcasts the active charge so a phone can "tap" it:
/// - Bluetooth LE peripheral (real iPhone — phone triggers on strong RSSI = physically touching)
/// - Bonjour TXT record (iOS Simulator / same network)
final class TapBeacon: NSObject, CBPeripheralManagerDelegate {
    private var peripheral: CBPeripheralManager!
    private var characteristic: CBMutableCharacteristic?
    private var listener: NWListener?
    private var request: PaymentRequest?
    private var serviceAdded = false
    private(set) var bluetoothOn = false
    var name = "Tapnad POS"

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

    // MARK: Bonjour

    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { $0.cancel() }
            l.stateUpdateHandler = { _ in }
            listener = l
            updateBonjour()
            l.start(queue: .main)
        } catch {
            print("Bonjour listener failed: \(error)")
        }
    }

    private func updateBonjour() {
        var fields = request?.fields ?? [:]
        fields["state"] = request == nil ? "idle" : "charging"
        let txt = NWTXTRecord(fields)
        listener?.service = NWListener.Service(name: name, type: TapLink.bonjourType, domain: nil, txtRecord: txt.data)
    }

    // MARK: BLE

    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        bluetoothOn = p.state == .poweredOn
        guard bluetoothOn, !serviceAdded else { return }
        let c = CBMutableCharacteristic(type: CBUUID(string: TapLink.requestCharUUID),
                                        properties: [.read], value: nil, permissions: [.readable])
        let s = CBMutableService(type: CBUUID(string: TapLink.serviceUUID), primary: true)
        s.characteristics = [c]
        characteristic = c
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
}
