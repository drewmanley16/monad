import SwiftUI

/// Order board: paid orders flow New → Preparing → Ready → Picked up.
struct KitchenView: View {
    @EnvironmentObject var store: POSStore
    private let columns: [TicketStatus] = [.new, .preparing, .ready]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(columns, id: \.self) { status in
                let items = store.tickets.filter { $0.status == status }.sorted { $0.number < $1.number }
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(status.rawValue).font(T.sans(15, .semibold))
                        Text("\(items.count)").font(T.mono(13)).foregroundStyle(T.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 20).frame(height: 48)
                    Rule()
                    ScrollView {
                        VStack(spacing: 12) {
                            if items.isEmpty {
                                Text(status == .new ? "Paid orders show up here." : "Nothing here.").font(T.sans(13)).foregroundStyle(T.faint)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }
                            ForEach(items) { t in TicketCard(ticket: t) { store.advance(t) } }
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.never)
                }
                .frame(maxWidth: .infinity)
                .background(status == .ready ? T.bg : T.surface)
                if status != columns.last { VRule() }
            }
        }
        .animation(.snappy, value: store.tickets)
    }
}

struct TicketCard: View {
    let ticket: KitchenTicket
    let advance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("#\(ticket.number)").font(T.mono(22, .semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(ticket.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                        .font(T.sans(12)).foregroundStyle(T.dim)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(ticket.lines.enumerated()), id: \.offset) { _, l in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(l.qty)× \(l.name)").font(T.sans(14, .medium))
                        if let o = l.options, !o.isEmpty { Text(o).font(T.sans(12)).foregroundStyle(T.dim) }
                    }
                }
            }
            HStack {
                Text(shortAddress(ticket.payer)).font(T.mono(11.5)).foregroundStyle(T.faint)
                Spacer()
                Button(action: advance) {
                    Text(nextLabel).padding(.horizontal, 12).frame(height: 30)
                }
                .buttonStyle(PrimaryAction())
            }
        }
        .card(padding: 14)
        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
    }

    private var nextLabel: String {
        switch ticket.status {
        case .new: "Start"
        case .preparing: "Mark ready"
        case .ready: "Picked up"
        case .done: "Done"
        }
    }
}
