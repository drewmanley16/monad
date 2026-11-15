import SwiftUI
import Charts

struct ActivityView: View {
    @EnvironmentObject var store: POSStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity").font(.system(size: 28, weight: .semibold))
                    Text("Payments settle on Monad. Times measured from first sighting (Proposed).").foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    kpi("Gross volume", "\(MON.format(store.grossVolume, maxFraction: 3)) MON", "banknote")
                    kpi("Payments", "\(store.sales.count)", "creditcard")
                    kpi("Avg. time to finality", store.avgFinalityMs.map { "\($0) ms" } ?? "—", "bolt")
                    kpi("Block time", store.blockTimeMs.map { "\($0) ms" } ?? "—", "cube")
                }

                HStack(alignment: .top, spacing: 14) {
                    chart.frame(maxWidth: .infinity)
                    liveBlocks.frame(width: 300)
                }

                table
            }
            .padding(28)
        }
    }

    private func kpi(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: 14)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent payments").font(.headline)
            if store.sales.isEmpty {
                Text("No payments yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(Array(store.sales.prefix(24).reversed())) { s in
                    BarMark(x: .value("Time", s.date, unit: .second),
                            y: .value("MON", Double(s.event.amountWei).map { $0 / 1e18 } ?? 0))
                        .foregroundStyle(Brand.indigo.gradient)
                        .cornerRadius(4)
                }
                .chartYAxisLabel("MON")
                .frame(height: 180)
            }
        }
        .surface(radius: 14)
    }

    private var liveBlocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live blocks").font(.headline)
                Spacer()
                Circle().fill(store.connected ? Brand.success : .orange).frame(width: 7, height: 7)
            }
            ForEach(store.recentBlocks, id: \.id) { b in
                HStack {
                    Text("#\(b.number.formatted())").font(.system(.callout, design: .monospaced))
                    Spacer()
                    StatePill(state: b.state)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.recentBlocks.map(\.id))
        .surface(radius: 14)
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Payments").font(.headline).padding(16)
            Divider()
            HStack {
                Text("Time").frame(width: 110, alignment: .leading)
                Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                Text("Customer").frame(width: 120, alignment: .leading)
                Text("Finality").frame(width: 90, alignment: .trailing)
                Text("Status").frame(width: 100, alignment: .leading).padding(.leading, 16)
                Text("Amount").frame(width: 120, alignment: .trailing)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if store.sales.isEmpty {
                Text("Payments you receive appear here.").foregroundStyle(.secondary).padding(24)
            }
            ForEach(store.sales) { s in
                Link(destination: URL(string: Chain.explorerTx + s.event.txHash)!) {
                    HStack {
                        Text(s.date.formatted(date: .omitted, time: .standard)).frame(width: 110, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(s.event.memo.isEmpty ? "Payment" : s.event.memo).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                        Text(shortAddress(s.event.payer)).font(.system(.callout, design: .monospaced))
                            .frame(width: 120, alignment: .leading).foregroundStyle(.secondary)
                        Text(s.finalizedMs.map { "\($0) ms" } ?? "—").monospacedDigit().frame(width: 90, alignment: .trailing)
                        StatePill(state: s.states[CommitState.finalized.rawValue] != nil ? .finalized :
                                    s.states[CommitState.voted.rawValue] != nil ? .voted : .proposed)
                            .frame(width: 100, alignment: .leading).padding(.leading, 16)
                        Text("\(MON.format(s.event.amount, maxFraction: 4)) MON").monospacedDigit().fontWeight(.medium)
                            .frame(width: 120, alignment: .trailing)
                    }
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            }
        }
        .surface(radius: 14, padding: 0)
    }
}

struct StatePill: View {
    let state: CommitState
    var color: Color {
        switch state {
        case .proposed: .orange
        case .voted: .blue
        case .finalized: Brand.success
        case .verified: Brand.purple
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(state.rawValue)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct POSSettingsView: View {
    @EnvironmentObject var store: POSStore
    @State private var payoutDraft = ""

    var body: some View {
        Form {
            Section("Business") {
                TextField("Business name", text: $store.merchantName)
            }
            Section {
                TextField("Payout address", text: $payoutDraft)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(save)
                HStack {
                    if !isAddress(payoutDraft) { Text("Enter a valid 0x address").foregroundStyle(.red).font(.caption) }
                    Spacer()
                    Button("Save", action: save).disabled(!isAddress(payoutDraft) || payoutDraft == store.payout)
                }
            } header: { Text("Payouts") } footer: { Text("Payments go straight to this address on \(Chain.name).") }
            Section("Network") {
                LabeledContent("Chain", value: "\(Chain.name) (\(Chain.chainId))")
                LabeledContent("Settlement contract") { Text(shortAddress(Chain.monadPay)).font(.system(.body, design: .monospaced)) }
                LabeledContent("Tap discovery", value: "Bluetooth LE + Bonjour")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .padding(20)
        .onAppear { payoutDraft = store.payout }
    }

    private func save() {
        guard isAddress(payoutDraft) else { return }
        store.payout = payoutDraft
        store.connect()
    }
}
