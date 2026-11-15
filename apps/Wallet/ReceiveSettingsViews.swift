import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    @EnvironmentObject var store: WalletStore
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: qrImage(store.address)).interpolation(.none).resizable()
                    .frame(width: 200, height: 200).padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.06)))
                Text(store.address).font(.system(.footnote, design: .monospaced))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .padding(.horizontal, 40).textSelection(.enabled)
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = store.address; copied = true; Haptics.tap()
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(PrimaryButton())
                    Link(destination: Chain.faucet) {
                        Label("Faucet", systemImage: "drop.fill")
                            .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(SecondaryButton())
                }
                .padding(.horizontal, 24)
                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle("Add MON").navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }
}

func qrImage(_ string: String) -> UIImage {
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Network", value: Chain.name)
                    LabeledContent("Address") {
                        Text(shortAddress(store.address)).font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Tap mode", value: ReaderScanner.isSimulator ? "Local network" : "Bluetooth proximity")
                }
                Section {
                    Button(revealed == nil ? "Reveal Private Key" : "Hide Private Key") {
                        if revealed != nil { revealed = nil; return }
                        Task {
                            if await Biometrics.authenticate("Reveal private key"), let k = Keychain.load() { revealed = k.hex }
                        }
                    }
                    if let revealed {
                        Text(revealed).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    }
                } footer: { Text("Testnet only. Your key never leaves this device.") }

                Section {
                    SecureField("0x… private key", text: $importText)
                    Button("Import Wallet") {
                        importMsg = store.importKey(importText) ? "Imported" : "Invalid key"
                        importText = ""
                    }
                    if let importMsg { Text(importMsg).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Import") }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
