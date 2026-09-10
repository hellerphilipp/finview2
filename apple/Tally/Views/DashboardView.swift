import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage("staleDays") private var staleDays = 35
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]
    @Query private var allTransactions: [Transaction]

    private var pendingCount: Int { allTransactions.filter { $0.status == .pending }.count }
    private var recentSpend: [(name: String, amount: Decimal)] {
        Analytics.spendingByCategory(allTransactions, since: Calendar.current.date(byAdding: .day, value: -30, to: .now))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statRow
                accountsSection
                recentSpendingSection
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            StatTile(title: "Accounts", value: "\(accounts.count)", systemImage: "building.columns", tint: .blue) {
                router.selection = .accounts
            }
            StatTile(title: "Pending Review", value: "\(pendingCount)", systemImage: "tray.full",
                     tint: pendingCount > 0 ? .orange : .green) {
                router.selection = .review
            }
            StatTile(title: "Last 30 Days",
                     value: recentSpend.isEmpty ? "—" : Money.string(recentSpend.reduce(Decimal.zero) { $0 + $1.amount }, currency: accounts.first?.currencyCode ?? "CHF"),
                     systemImage: "creditcard", tint: .purple) {
                router.selection = .reports
            }
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts").font(.title3.bold())
            if accounts.isEmpty {
                Text("No accounts yet — add one in Accounts to begin.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(accounts) { AccountCard(account: $0, staleDays: staleDays) }
                }
            }
        }
    }

    private var recentSpendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending — Last 30 Days").font(.title3.bold())
            if recentSpend.isEmpty {
                Text("No spending recorded in the last 30 days.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(recentSpend.prefix(6)), id: \.name) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            Text(Money.string(entry.amount, currency: accounts.first?.currencyCode ?? "CHF"))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline).foregroundStyle(tint)
                Text(value).font(.title.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct AccountCard: View {
    let account: Account
    var staleDays: Int = 35

    private var balance: Decimal { Analytics.balance(of: account) }
    private var isStale: Bool { Analytics.isStale(account, days: staleDays) }
    private var lastActivity: Date? { Analytics.lastActivity(of: account) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color(hex: account.colorHex)).frame(width: 10, height: 10)
                Text(account.name).font(.headline).lineLimit(1)
                Spacer()
                Text(account.currencyCode).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text(Money.string(balance, currency: account.currencyCode))
                .font(.title2.bold()).monospacedDigit()
                .foregroundStyle(balance < 0 ? Color.primary : Color.green)

            HStack(spacing: 4) {
                if isStale {
                    Label("Import needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                } else if let lastActivity {
                    Label(DateText.string(lastActivity), systemImage: "clock").font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No data").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isStale ? Color.orange.opacity(0.5) : .clear))
    }
}
