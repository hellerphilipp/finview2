import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var router = AppRouter()
    @State private var transactionsExpanded = true
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]
    @Query(filter: #Predicate<Transaction> { $0.statusRaw == "pending" })
    private var pending: [Transaction]
    @AppStorage("showUnreviewedBadges") private var showUnreviewedBadges = true

    private func pendingCount(_ accountID: UUID) -> Int {
        guard showUnreviewedBadges else { return 0 }
        return pending.filter { $0.account?.id == accountID }.count
    }

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.selection) {
                Label("Dashboard", systemImage: "gauge.medium").tag(NavTarget.dashboard)

                Section("Activity") {
                    DisclosureGroup(isExpanded: $transactionsExpanded) {
                        Label("All Transactions", systemImage: "tray.full")
                            .badge(showUnreviewedBadges ? pending.count : 0)
                            .tag(NavTarget.transactionsAll)
                        ForEach(accounts) { account in
                            Label(account.name, systemImage: "creditcard")
                                .badge(pendingCount(account.id))
                                .tag(NavTarget.account(account.id))
                        }
                    } label: {
                        Label("Transactions", systemImage: "list.bullet.rectangle")
                    }
                    Label("Transfers", systemImage: "arrow.left.arrow.right").tag(NavTarget.transfers)
                    Label("Recurring", systemImage: "repeat").tag(NavTarget.recurring)
                    Label("Reports", systemImage: "chart.bar").tag(NavTarget.reports)
                }

                Section("Manage") {
                    Label("Accounts", systemImage: "building.columns").tag(NavTarget.accounts)
                    Label("Categories", systemImage: "tag").tag(NavTarget.categories)
                }
            }
            .navigationTitle("Tally")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            detail(for: router.selection ?? .dashboard)
                .id(router.selection)
                .frame(minWidth: 520, minHeight: 380)
        }
        .environment(router)
    }

    @ViewBuilder
    private func detail(for target: NavTarget) -> some View {
        switch target {
        case .dashboard: DashboardView()
        case .transactionsAll: TransactionsView(accountID: nil)
        case .account(let id): TransactionsView(accountID: id)
        case .transfers: TransfersView()
        case .recurring: RecurringView()
        case .reports: ReportsView()
        case .accounts: AccountsView()
        case .categories: CategoriesView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(Persistence.makeContainer(inMemory: true))
}
