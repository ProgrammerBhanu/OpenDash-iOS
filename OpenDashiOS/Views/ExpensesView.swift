import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject private var store: OpenDashStore
    @State private var selectedCategory: ExpenseCategory = .fuel
    @State private var amount = 0.0
    @State private var note = ""
    @State private var monthOnly = true
    @State private var exportURL: URL?

    private var selectedExpenses: [ExpenseItem] {
        monthOnly ? store.monthlyExpenses : store.activeExpenses
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(
                        title: "Expenses",
                        subtitle: "Fuel, repairs, gear, food, stays, and ride spending."
                    )

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricTile(title: "Selected total", value: selectedExpenses.reduce(0.0) { $0 + $1.amount }.currencyText, footnote: monthOnly ? "This month" : "All time")
                        MetricTile(title: "Entries", value: "\(selectedExpenses.count)", footnote: store.activeVehicle.name)
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Add expense")
                                .font(.headline)
                                .foregroundStyle(OpenDashTheme.textPrimary)

                            Picker("Category", selection: $selectedCategory) {
                                ForEach(ExpenseCategory.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(OpenDashTheme.gold)

                            TextField("Amount", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Note", text: $note)
                                .textFieldStyle(.roundedBorder)

                            PrimaryButton(title: "Add expense", systemImage: "plus") {
                                guard amount > 0 else { return }
                                store.addExpense(category: selectedCategory, amount: amount, note: note)
                                amount = 0
                                note = ""
                            }
                        }
                    }

                    OpenDashCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("History")
                                    .font(.headline)
                                    .foregroundStyle(OpenDashTheme.textPrimary)
                                Spacer()
                                Picker("Period", selection: $monthOnly) {
                                    Text("Month").tag(true)
                                    Text("All").tag(false)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 150)
                            }

                            HStack(spacing: 10) {
                                SecondaryButton(title: "Prepare CSV", systemImage: "doc.plaintext") {
                                    exportURL = store.exportExpensesCSV(monthOnly: monthOnly)
                                }
                                if let exportURL {
                                    ShareLink(item: exportURL) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.black)
                                    .background(OpenDashTheme.gold)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }

                            if selectedExpenses.isEmpty {
                                EmptyState(title: "No expenses", subtitle: "Add a cost to see it here.", systemImage: "chart.bar")
                            } else {
                                ForEach(selectedExpenses) { expense in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon(for: expense.category))
                                            .foregroundStyle(OpenDashTheme.gold)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(expense.category.rawValue)
                                                .foregroundStyle(OpenDashTheme.textPrimary)
                                            Text(expense.note.isEmpty ? expense.date.formatted(date: .abbreviated, time: .omitted) : expense.note)
                                                .font(.caption)
                                                .foregroundStyle(OpenDashTheme.textSecondary)
                                        }
                                        Spacer()
                                        Text(expense.amount.currencyText)
                                            .font(.headline)
                                            .foregroundStyle(OpenDashTheme.textPrimary)
                                        Button(role: .destructive) {
                                            store.deleteExpense(expense)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    Divider().overlay(Color.white.opacity(0.08))
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .openDashScreenBackground()
        }
    }

    private func icon(for category: ExpenseCategory) -> String {
        switch category {
        case .fuel: return "fuelpump"
        case .repairs: return "wrench.and.screwdriver"
        case .accessories: return "bag"
        case .ridingGear: return "helmet"
        case .food: return "fork.knife"
        case .stays: return "bed.double"
        case .transport: return "tram"
        case .other: return "ellipsis.circle"
        }
    }
}
