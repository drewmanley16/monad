import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    @EnvironmentObject var store: WalletStore
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(uiImage: qr(store.address)).interpolation(.none).resizable()
                    .frame(width: 240, height: 240).padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                Text(store.address).font(.system(.footnote, design: .monospaced)).multilineTextAlignment(.center)
                    .padding(.horizontal, 32).textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = store.address; copied = true; Haptics.tap()
                } label: {
                    Label(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                Link("Get testnet MON from the faucet", destination: Chain.faucet).font(.footnote)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Add MON").navigationBarTitleDisplayMode(.inline)
        }
    }
}

func qr(_ string: String) -> UIImage {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(string.utf8)
    f.correctionLevel = "M"
    guard let out = f.outputImage?.transformed(by: .init(scaleX: 10, y: 10)),
          let cg = CIContext().createCGImage(out, from: out.extent) else { return UIImage() }
    return UIImage(cgImage: cg)
}

struct SettingsView: View {
    @EnvironmentObject var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var importText = ""
    @State private var importMsg: String?
    @State private var revealed: String?

    // Tag writer
    @State private var tagName = "Tapnad Café"
    @State private var tagMemo = "Coffee"
    @State private var tagAmount = "0.05"
    @State private var tagMerchant = ""
    @State private var tagMsg: String?
    @State private var nfc = NFCReader()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Merchant name", text: $tagName)
                    TextField("Item / memo", text: $tagMemo)
                    TextField("Amount (MON)", text: $tagAmount).keyboardType(.decimalPad)
                    TextField("Merchant address", text: $tagMerchant)
                        .font(.system(.footnote, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Write NFC Reader Tag") { writeTag() }
                    if let tagMsg { Text(tagMsg).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Program a Tap Reader") } footer: {
                    Text("Writes a monadpay:// payment link onto a blank NTAG sticker. Tapping it opens checkout.")
                }

                Section("Wallet") {
                    LabeledContent("Network", value: "Monad Testnet (10143)")
                    LabeledContent("Address", value: "\(store.address.prefix(8))…\(store.address.suffix(6))")
                    Button(revealed == nil ? "Reveal Private Key" : "Hide Private Key") {
                        if revealed != nil { revealed = nil; return }
                        Task {
                            if await Biometrics.authenticate("Reveal private key"),
                               let k = Keychain.load() { revealed = k.hex }
                        }
                    }
                    if let revealed {
                        Text(revealed).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                }

                Section {
                    SecureField("0x… private key", text: $importText)
                    Button("Import") {
                        importMsg = store.importKey(importText) ? "Imported ✓" : "Invalid key"
                        importText = ""
                    }
                    if let importMsg { Text(importMsg).font(.footnote) }
                } header: { Text("Import Wallet") } footer: {
                    Text("Testnet only. Replaces the on-device key.")
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if tagMerchant.isEmpty { tagMerchant = store.address } }
        }
    }

    private func writeTag() {
        guard EthAccount.isValid(tagMerchant), let amt = MON.parse(tagAmount), amt > 0 else {
            tagMsg = "Check the address and amount."; return
        }
        let req = PaymentRequest(merchant: tagMerchant, amount: amt, invoiceId: Data(), memo: tagMemo, merchantName: tagName)
        nfc.write(req.url) { url in tagMsg = url == nil ? "Cancelled" : "Tag written ✓" }
    }
}
