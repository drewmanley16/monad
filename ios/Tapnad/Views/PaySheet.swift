import SwiftUI

struct PaySheet: View {
    @EnvironmentObject var store: WalletStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let req = store.pending {
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { store.dismissPayment() }
                        .opacity(store.phase == .confirm || isFailed ? 1 : 0)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 16)

                Spacer(minLength: 12)

                header(req)

                Spacer(minLength: 20)

                if store.phase == .inFlight || store.phase == .done {
                    timeline.transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if case .failed(let msg) = store.phase {
                    Text(msg).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                }

                Spacer(minLength: 20)

                bottom(req).padding(.horizontal, 20).padding(.bottom, 24)
            }
            .animation(.spring(duration: 0.4), value: store.phase)
            .foregroundStyle(.white)
        }
    }

    private var isFailed: Bool { if case .failed = store.phase { return true }; return false }

    @ViewBuilder private func header(_ req: PaymentRequest) -> some View {
        VStack(spacing: 18) {
            ZStack {
                if store.phase == .done {
                    Circle().fill(Color.green).frame(width: 96, height: 96)
                    Image(systemName: "checkmark").font(.system(size: 44, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    CardView(balance: nil, address: store.address, compact: true).frame(width: 220)
                    if store.phase == .sending || store.phase == .inFlight {
                        ProgressView().controlSize(.large).tint(.white)
                    }
                }
            }
            .frame(height: 140)

            VStack(spacing: 6) {
                Text(req.merchantName).font(.title3.weight(.semibold))
                if !req.memo.isEmpty { Text(req.memo).foregroundStyle(.secondary) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(MON.format(req.amount, maxFraction: 6)).font(.system(size: 52, weight: .semibold, design: .rounded))
                    Text("MON").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(store.phase == .done ? "Done" : "to \(req.merchant.prefix(6))…\(req.merchant.suffix(4))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(store.steps.enumerated()), id: \.element.id) { i, step in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(step.ms != nil ? Color.monadPurple : Color(white: 0.2)).frame(width: 22, height: 22)
                        if step.ms != nil { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                    }
                    Text(step.label).font(.body.weight(.medium)).opacity(step.ms != nil ? 1 : 0.45)
                    Spacer()
                    Text(step.ms.map { $0 == 0 ? "0 ms" : "+\($0) ms" } ?? "…")
                        .font(.body.monospacedDigit()).foregroundStyle(step.ms != nil ? .white : .secondary)
                        .contentTransition(.numericText())
                }
                .padding(.vertical, 9)
                if i < store.steps.count - 1 {
                    Rectangle().fill(Color(white: 0.2)).frame(width: 2, height: 10).padding(.leading, 10)
                }
            }
            if let hash = store.lastTxHash {
                Link(destination: URL(string: Chain.explorerTx + hash)!) {
                    Label("View on explorer", systemImage: "arrow.up.right.square").font(.footnote)
                }
                .padding(.top, 10)
            }
        }
        .padding(18)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    @ViewBuilder private func bottom(_ req: PaymentRequest) -> some View {
        switch store.phase {
        case .confirm, .failed:
            VStack(spacing: 10) {
                Button { Task { await store.pay() } } label: {
                    Label("Pay with Face ID", systemImage: "faceid")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.black)
                }
                if let bal = store.balance, bal < req.amount {
                    Text("Insufficient balance (\(MON.format(bal)) MON)").font(.footnote).foregroundStyle(.orange)
                }
            }
        case .authorizing:
            Label("Confirm with Face ID", systemImage: "faceid").font(.headline).foregroundStyle(.secondary)
        case .sending:
            Text("Sending…").font(.headline).foregroundStyle(.secondary)
        case .inFlight, .done:
            Button { store.dismissPayment() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .idle:
            EmptyView()
        }
    }
}
