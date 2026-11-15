import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject var store: WalletStore
    var embedded = false
    @State private var month = Date.now
    @State private var scope: Scope = .all
    @State private var editingBudget: ExpenseCategory?
    @State private var budgetText = ""

    enum Scope: String, CaseIterable, Identifiable { case all = "All", personal = "Personal", business = "Business"; var id: String { rawValue } }

    private var recs: [PaymentRecord] {
        store.records(inMonthOf: month).filter { r in
            let biz = store.card(for: r)?.isBusiness ?? false
            return scope == .all || (scope == .business) == biz
        }
    }

    private var byCategory: [(cat: ExpenseCategory, total: Double, count: Int)] {
        Dictionary(grouping: recs, by: \.resolvedCategory)
            .map { ($0.key, store.spend($0.value), $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        let content = ScrollView {
            VStack(spacing: 18) {
                header
                Picker("Scope", selection: $scope) { ForEach(Scope.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                donut
                daily
                budgets
                export
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Insights")
        .alert("Monthly budget", isPresented: Binding(get: { editingBudget != nil }, set: { if !$0 { editingBudget = nil } })) {
            TextField("MON per month", text: $budgetText).keyboardType(.decimalPad)
            Button("Save") {
                if let c = editingBudget { store.budgets[c] = Double(budgetText).flatMap { $0 > 0 ? $0 : nil } }
                editingBudget = nil
            }
            Button("Cancel", role: .cancel) { editingBudget = nil }
        } message: { Text(editingBudget?.name ?? "") }

        if embedded { content } else { NavigationStack { content } }
    }

    private var header: some View {
        HStack {
            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Text("\(recs.count) payments").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .font(.body.weight(.semibold))
    }

    private var donut: some View {
        let total = store.spend(recs)
        return VStack(spacing: 16) {
            ZStack {
                Chart(byCategory, id: \.cat) { item in
                    SectorMark(angle: .value("MON", item.total), innerRadius: .ratio(0.68), angularInset: 2)
                        .foregroundStyle(item.cat.color)
                        .cornerRadius(5)
                }
                .chartLegend(.hidden)
                .frame(height: 220)
                if byCategory.isEmpty {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 34).frame(width: 186)
                }
                VStack(spacing: 2) {
                    Text("Spent").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.3f", total)).font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("MON").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(byCategory, id: \.cat) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.cat.icon).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(item.cat.color, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.cat.name).font(.subheadline.weight(.medium))
                            Text("\(item.count) payment\(item.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.3f MON", item.total)).font(.subheadline.monospacedDigit().weight(.medium))
                            Text(total > 0 ? "\(Int(item.total / total * 100))%" : "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .surface()
    }

    private var daily: some View {
        let cal = Calendar.current
        let days = Dictionary(grouping: recs) { cal.startOfDay(for: $0.date) }.map { ($0.key, store.spend($0.value)) }.sorted { $0.0 < $1.0 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Daily spend").font(.subheadline.weight(.semibold))
            Chart(days, id: \.0) { d in
                BarMark(x: .value("Day", d.0, unit: .day), y: .value("MON", d.1))
                    .foregroundStyle(Color.primary).cornerRadius(4)
            }
            .chartXScale(domain: monthRange)
            .frame(height: 140)
        }
        .surface()
    }

    private var monthRange: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        return start...end
    }

    private var budgets: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Budgets").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Tap to set").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(ExpenseCategory.allCases) { cat in
                let spent = byCategory.first { $0.cat == cat }?.total ?? 0
                let budget = store.budgets[cat]
                Button {
                    editingBudget = cat
                    budgetText = budget.map { String($0) } ?? ""
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(cat.name, systemImage: cat.icon).font(.subheadline)
                            Spacer()
                            Text(budget.map { String(format: "%.2f / %.2f", spent, $0) } ?? String(format: "%.3f", spent))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.12))
                                if let budget, budget > 0 {
                                    Capsule().fill(spent > budget ? Color.red : cat.color)
                                        .frame(width: max(6, g.size.width * min(1, spent / budget)))
                                }
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .surface()
    }

    private var export: some View {
        let url = store.exportCSV(recs)
        let bizTotal = store.spend(store.records(inMonthOf: month).filter { store.card(for: $0)?.isBusiness ?? false })
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expense report").font(.subheadline.weight(.semibold))
                    Text(String(format: "Business spend this month: %.3f MON", bizTotal)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ShareLink(item: url) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(PrimaryButton())
        }
        .surface()
    }
}
