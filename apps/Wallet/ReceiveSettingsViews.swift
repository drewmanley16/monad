import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceiveView: View {
    @EnvironmentObject var store: WalletStore
    @State private var copied = false
    @State private var adding = false
    @State private var faucetMsg: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Button {
                    adding = true; faucetMsg = nil
                    Task { let err = await store.requestTestMoney(); adding = false; faucetMsg = err ?? "Added! Your balance will update in a moment."; if err == nil { Haptics.success() } }
                } label: {
                    HStack { if adding { ProgressView().tint(.white) }; Text(adding ? "Adding…" : "Add $10 test money") }
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(PrimaryButton())
                .disabled(adding)
                .padding(.horizontal, 24)
                if let faucetMsg { Text(faucetMsg).font(.footnote).foregroundStyle(.secondary) }
                Text("Or send money to this card").font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
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
            .navigationTitle("Add money").navigationBarTitleDisplayMode(.inline)
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
    @State private var revealed: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section("Overview") {
                    LabeledContent("Network", value: Chain.name)
                    LabeledContent("Total balance", value: "\(Money.usd(store.totalBalance))")
                    LabeledContent("Tap mode", value: ReaderScanner.isSimulator ? "Local network" : "Bluetooth proximity")
                }
                ForEach(store.cards) { card in
                    Section {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 5).fill(card.theme.gradient).frame(width: 40, height: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.name).font(.body.weight(.medium))
                                Text(card.address).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Button(revealed[card.id] == nil ? "Reveal Private Key" : "Hide Private Key") {
                            if revealed[card.id] != nil { revealed[card.id] = nil; return }
                            Task {
                                if await Biometrics.authenticate("Reveal private key"), let k = store.privateKeyHex(card) { revealed[card.id] = k }
                            }
                        }
                        if let k = revealed[card.id] {
                            Text(k).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        }
                    } header: { Text(card.isBusiness ? "Business card" : "Card") }
                }
                Section {} footer: { Text("Testnet only. Keys never leave this device.") }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
