import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard, review, transfers, workExpenses, importer, accounts, categories, reports, currencies, recurring
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .review: "Review"
        case .transfers: "Transfers"
        case .workExpenses: "Work Expenses"
        case .importer: "Import"
        case .accounts: "Accounts"
        case .categories: "Categories"
        case .reports: "Reports"
        case .currencies: "Currencies"
        case .recurring: "Recurring"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.medium"
        case .review: "tray.full"
        case .transfers: "arrow.left.arrow.right"
        case .workExpenses: "briefcase"
        case .importer: "square.and.arrow.down"
        case .accounts: "building.columns"
        case .categories: "tag"
        case .reports: "chart.bar"
        case .currencies: "globe"
        case .recurring: "repeat"
        }
    }
}

struct ContentView: View {
    @State private var router = AppRouter()

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $router.selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Tally")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail(for: router.selection ?? .dashboard)
                .frame(minWidth: 480, minHeight: 360)
        }
        .environment(router)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard: DashboardView()
        case .review: ReviewView()
        case .transfers: TransfersView()
        case .workExpenses: WorkExpensesView()
        case .importer: ImportView()
        case .accounts: AccountsView()
        case .categories: CategoriesView()
        case .reports: ReportsView()
        case .currencies: CurrenciesView()
        case .recurring: RecurringView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(Persistence.makeContainer(inMemory: true))
}
