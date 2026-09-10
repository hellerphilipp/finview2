import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    /// nil = all accounts; otherwise scope to this account.
    let accountID: UUID?

    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query private var merchants: [Merchant]
    @Query private var accounts: [Account]
    @Query(sort: [SortDescriptor(\SpendingCategory.sortOrder)]) private var categories: [SpendingCategory]

    @State private var statusFilter: StatusFilter = .all
    @State private var sortOrder = [KeyPathComparator(\Transaction.date, order: .reverse)]
    @State private var selection = Set<UUID>()
    @State private var showingPalette = false
    @State private var showingImport = false
    /// Cached so they aren't recomputed per row while scrolling.
    @State private var missingWorkIDs: Set<UUID> = []
    @State private var suggestions: [UUID: SpendingCategory] = [:]
    @StateObject private var actions = ReviewActions()

    private var account: Account? { accounts.first { $0.id == accountID } }

    private var transactions: [Transaction] {
        allTransactions
            .filter { tx in (accountID == nil || tx.account?.id == accountID) && statusFilter.matches(tx) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if transactions.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "tray",
                                       description: Text(emptyMessage))
            } else {
                table
            }
        }
        .navigationTitle(account?.name ?? "Transactions")
        .toolbar { toolbarContent }
        .focusedSceneValue(\.reviewActions, actions)
        .onAppear {
            wireActions()
            if let requested = router.requestedStatus {
                statusFilter = requested
                router.requestedStatus = nil
            }
            propagateWorkCategories()
            recomputeMissingWork()
            recomputeSuggestions()
        }
        .onChange(of: selection) { actions.hasSelection = !selection.isEmpty }
        .onChange(of: allTransactions) { recomputeMissingWork(); recomputeSuggestions() }
        .onChange(of: merchants) { recomputeSuggestions() }
        .sheet(isPresented: $showingPalette) {
            CategoryPalette(categories: categories) { assignCategory($0) }
        }
        .sheet(isPresented: $showingImport) {
            NavigationStack {
                ImportView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingImport = false }
                        }
                    }
            }
            .frame(minWidth: 640, minHeight: 460)
        }
    }

    private var table: some View {
        Table(transactions, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { tx in
                Text(DateText.string(tx.date))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 96, ideal: 104)
            TableColumn("Account", value: \.accountName) { Text($0.account?.name ?? "—") }
            TableColumn("Description", value: \.descriptionText) { Text($0.descriptionText).lineLimit(1) }
            TableColumn("Amount", value: \.amount) { tx in amountCell(tx) }
                .width(min: 120, ideal: 140)
            TableColumn("Category", value: \.categorySortKey) { tx in
                CategoryCell(tx: tx, categories: categories, suggestion: suggestion(for: tx))
            }
            .width(min: 150, ideal: 210, max: 320)
            TableColumn("Work") { tx in workCell(tx) }.width(60)
            TableColumn("Status", value: \.statusRaw) { tx in statusBadge(tx) }.width(90)
        }
        .contextMenu(forSelectionType: UUID.self) { _ in
            Button("Assign Category…") { showingPalette = true }
            Button("Toggle Work Expense") { toggleWork() }
            Divider()
            Button("Confirm") { confirmSelection() }
            Button("Reject", role: .destructive) { rejectSelection() }
        }
    }

    /// Currency code pinned left, number right-aligned, flexible gap between.
    private func amountCell(_ tx: Transaction) -> some View {
        HStack(spacing: 8) {
            Text(tx.account?.currencyCode ?? "").foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(Money.amount(tx.amount))
                .monospacedDigit()
                .foregroundStyle(tx.amount < 0 ? Color.primary : Color.green)
        }
        .frame(maxWidth: .infinity)
    }

    private func workCell(_ tx: Transaction) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tx.isWorkExpense ? "briefcase.fill" : "briefcase")
                .foregroundStyle(tx.isWorkExpense ? Color.accentColor : Color.secondary)
                .onTapGesture { tx.isWorkExpense.toggle(); try? context.save() }
            if missingWorkIDs.contains(tx.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Not yet posted to your work expense account")
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ tx: Transaction) -> some View {
        switch tx.status {
        case .pending: Text("To Review").foregroundStyle(.orange)
        case .confirmed: Text("Confirmed").foregroundStyle(.secondary)
        case .rejected: Text("Rejected").foregroundStyle(.red)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showingPalette = true } label: { Label("Assign Category", systemImage: "tag") }
                .disabled(selection.isEmpty)
                .keyboardShortcut("k", modifiers: .command)
            Button { toggleWork() } label: { Label("Work", systemImage: "briefcase") }
                .disabled(selection.isEmpty)
                .keyboardShortcut("w", modifiers: .command)
            Button { confirmSelection() } label: { Label("Confirm", systemImage: "checkmark") }
                .disabled(selection.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)

            Menu {
                Button("Import Statement…") { showingImport = true }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    // MARK: Empty-state text

    private var emptyTitle: String {
        switch statusFilter {
        case .toReview: "All Caught Up"
        default: "No Transactions"
        }
    }
    private var emptyMessage: String {
        switch statusFilter {
        case .toReview: "Nothing to review here."
        case .confirmed: "No confirmed transactions yet."
        case .all: account == nil ? "Import a statement to get started (＋ in the toolbar)." : "No transactions for this account yet."
        }
    }

    // MARK: Suggestions + actions

    private func suggestion(for tx: Transaction) -> SpendingCategory? {
        // Only surface the "?" suggestion while a transaction still needs review.
        guard tx.category == nil, tx.status == .pending else { return nil }
        return suggestions[tx.id]
    }

    private func recomputeSuggestions() {
        var map: [UUID: SpendingCategory] = [:]
        for tx in allTransactions where tx.category == nil {
            if let s = AutoTagger.suggest(for: tx.descriptionText, merchants: merchants) { map[tx.id] = s }
        }
        suggestions = map
    }

    private func selectedTransactions() -> [Transaction] {
        transactions.filter { selection.contains($0.id) }
    }

    private func assignCategory(_ category: SpendingCategory) {
        for tx in selectedTransactions() {
            tx.category = category
            AutoTagger.learn(description: tx.descriptionText, category: category, in: context)
        }
        try? context.save()
        propagateWorkCategories()
        recomputeSuggestions()
    }

    private func acceptSuggestions() {
        for tx in selectedTransactions() {
            if let s = AutoTagger.suggest(for: tx.descriptionText, merchants: merchants) { tx.category = s }
        }
        try? context.save()
        propagateWorkCategories()
        recomputeSuggestions()
    }

    /// After categorizing, let matched expense-account line items inherit the
    /// category of their originating work charge.
    private func propagateWorkCategories() {
        let result = ExpenseReconciler.reconcile(transactions: allTransactions, accounts: accounts)
        ExpenseReconciler.inheritCategories(from: result, in: context)
    }

    /// Recompute the cached set of unmatched work-charge IDs (drives ⚠️).
    private func recomputeMissingWork() {
        missingWorkIDs = Set(ExpenseReconciler.reconcile(transactions: allTransactions, accounts: accounts)
            .missing.map(\.id))
    }

    private func toggleWork() {
        let txs = selectedTransactions()
        let allWork = txs.allSatisfy(\.isWorkExpense)
        txs.forEach { $0.isWorkExpense = !allWork }
        try? context.save()
        recomputeMissingWork()
    }

    private func confirmSelection() {
        // Confirming with an accepted suggestion applies it — the user has
        // verified the auto-tag, so it becomes a real category (no more wand/?).
        for tx in selectedTransactions() where tx.category == nil {
            if let s = suggestions[tx.id] {
                tx.category = s
                AutoTagger.learn(description: tx.descriptionText, category: s, in: context)
            }
        }
        setStatus(.confirmed)
        recomputeSuggestions()
        propagateWorkCategories()
    }
    private func rejectSelection() { setStatus(.rejected) }

    private func setStatus(_ status: TransactionStatus) {
        selectedTransactions().forEach { $0.status = status }
        selection.removeAll()
        try? context.save()
        recomputeMissingWork()
    }

    private func wireActions() {
        actions.confirm = { confirmSelection() }
        actions.reject = { rejectSelection() }
        actions.toggleWork = { toggleWork() }
        actions.assignCategory = { showingPalette = true }
        actions.acceptSuggestion = { acceptSuggestions() }
        actions.hasSelection = !selection.isEmpty
    }
}
