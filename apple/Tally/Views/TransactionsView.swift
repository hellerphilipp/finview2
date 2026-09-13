import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// CSV payload for dragging transaction rows out to Finder/Numbers/Mail.
struct TransactionsCSV: Transferable {
    let csv: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.csv.utf8) }
        ProxyRepresentation(exporting: \.csv)
    }
}

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
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\Transaction.date, order: .reverse)]
    @State private var selection = Set<UUID>()
    /// When on, the table shows only the auto-matcher's suggested transfer legs
    /// (across all accounts), each pair adjacent, so they can be linked.
    @State private var showSuggestedTransfers = false
    /// Cached suggested transfer pairs (drives the funnel count + filtered rows).
    @State private var transferCandidates: [TransferMatcher.Candidate] = []
    @State private var showingPalette = false
    @State private var showingImport = false
    /// Cached so they aren't recomputed per row while scrolling.
    @State private var missingWorkIDs: Set<UUID> = []
    @State private var suggestions: [UUID: SpendingCategory] = [:]
    @StateObject private var actions = ReviewActions()

    private var account: Account? { accounts.first { $0.id == accountID } }

    /// The rows to display plus the ids to render dimmed (a linked partner that
    /// the status filter / search hid, pulled back in for context).
    private var linkedDisplay: (rows: [Transaction], context: Set<UUID>) {
        if showSuggestedTransfers {
            // Ignore account scope / status filter / sort so each suggested
            // pair stays adjacent and ready to select-and-link.
            return (transferCandidates.flatMap { [$0.outgoing, $0.incoming] }, [])
        }
        let terms = searchTerms(searchText)
        let universe = allTransactions.filter { accountID == nil || $0.account?.id == accountID }
        let (visible, context) = LinkGrouping.expandWithContext(universe) { tx in
            statusFilter.matches(tx) && tx.matches(searchTerms: terms)
        }
        // Sort, then keep each link group's members adjacent under their anchor.
        let ordered = LinkGrouping.orderedForDisplay(visible.sorted(using: sortOrder))
        return (ordered, context)
    }

    private var transactions: [Transaction] { linkedDisplay.rows }
    private var contextIDs: Set<UUID> { linkedDisplay.context }

    /// A linked partner shown only for context (its sibling matched the filter).
    private func isContext(_ tx: Transaction) -> Bool { contextIDs.contains(tx.id) }

    var body: some View {
        Group {
            if transactions.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "tray",
                                           description: Text(emptyMessage))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                table
            }
        }
        .navigationTitle(account?.name ?? "Transactions")
        .searchable(text: $searchText, prompt: "Search transactions")
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
            recomputeTransferCandidates()
        }
        .onChange(of: selection) { actions.hasSelection = !selection.isEmpty }
        .onChange(of: allTransactions) { recomputeMissingWork(); recomputeSuggestions(); recomputeTransferCandidates() }
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
        Table(of: Transaction.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { tx in
                Text(DateText.string(tx.date))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(dim(tx))
            }
            .width(min: 96, ideal: 104)
            TableColumn("Account", value: \.accountName) { tx in
                Text(tx.account?.name ?? "—").opacity(dim(tx))
            }
            TableColumn("Description", value: \.descriptionText) { tx in
                HStack(spacing: 6) {
                    if tx.isLinked {
                        Image(systemName: linkGlyph(tx))
                            .foregroundStyle(.tint)
                            .help(linkHelp(tx))
                    }
                    Text(tx.descriptionText).lineLimit(1)
                }
                .opacity(dim(tx))
            }
            TableColumn("Amount", value: \.amount) { tx in amountCell(tx).opacity(dim(tx)) }
                .width(min: 120, ideal: 140)
            TableColumn("Category", value: \.categorySortKey) { tx in
                CategoryCell(tx: tx, categories: categories, suggestion: suggestion(for: tx))
                    .opacity(dim(tx))
            }
            .width(min: 150, ideal: 210, max: 320)
            TableColumn("Work") { tx in workCell(tx).opacity(dim(tx)) }.width(60)
            TableColumn("Status", value: \.statusRaw) { tx in statusBadge(tx).opacity(dim(tx)) }.width(90)
        } rows: {
            ForEach(transactions) { tx in
                TableRow(tx)
                    .draggable(TransactionsCSV(csv: ExportService.csv(for: [tx])))
            }
        }
        .contextMenu(forSelectionType: UUID.self) { _ in
            Button("Assign Category…") { showingPalette = true }
            Button("Toggle Work Expense") { toggleWork() }
            Divider()
            Button("Confirm") { confirmSelection() }
            Button("Reject", role: .destructive) { rejectSelection() }
            let selected = selectedTransactions()
            if TransferMatcher.canLink(selected) {
                Divider()
                Button { linkTransfer() } label: {
                    Label("Link as Transfer", systemImage: "arrow.left.arrow.right")
                }
            }
            if LinkService.canLinkRefund(selected) {
                if !TransferMatcher.canLink(selected) { Divider() }
                Button { linkRefund() } label: {
                    Label("Link as Refund", systemImage: "arrow.uturn.backward")
                }
            }
            if selected.contains(where: { $0.isLinked }) {
                Divider()
                Button { unlinkSelection() } label: {
                    Label("Unlink", systemImage: "link.badge.plus")
                }
            }
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
                ForEach(StatusFilter.allCases) { filter in
                    Text(segmentLabel(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ZStack(alignment: .topTrailing) {
                Menu {
                    Toggle(isOn: $showSuggestedTransfers) {
                        Text("Suggested Transfers")
                    }
                    .badge(transferCandidates.count)
                    .disabled(transferCandidates.isEmpty && !showSuggestedTransfers)
                } label: {
                    Label("Filter", systemImage: showSuggestedTransfers
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .help("Show suggested transfers to link")

                // Overlaid as a sibling (not inside the Menu label) so the
                // toolbar doesn't flatten it to a monochrome template.
                CountBubble(count: transferCandidates.count)
                    .allowsHitTesting(false)
                    .offset(x: 5, y: -6)
            }

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

    /// Pending (unreviewed) transactions in the current account scope.
    private var pendingCount: Int {
        allTransactions.filter {
            (accountID == nil || $0.account?.id == accountID) && $0.status == .pending
        }.count
    }

    /// Segment title; the "To Review" segment carries a live unreviewed count.
    private func segmentLabel(_ filter: StatusFilter) -> String {
        if filter == .toReview, pendingCount > 0 { return "\(filter.label) (\(pendingCount))" }
        return filter.label
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
        let selected = selectedTransactions()
        for tx in selected {
            tx.category = category
            AutoTagger.learn(description: tx.descriptionText, category: category, in: context)
        }
        // Keep every link group's "one shared category" invariant: a recategorized
        // member drags its whole group (incl. a dimmed partner) along.
        for gid in Set(selected.compactMap { $0.linkGroupID }) {
            LinkService.propagateCategory(category, groupID: gid, among: allTransactions, context: context)
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

    private func recomputeTransferCandidates() {
        transferCandidates = TransferMatcher.candidates(allTransactions)
        if transferCandidates.isEmpty { showSuggestedTransfers = false }
    }

    private func linkTransfer() {
        TransferMatcher.link(selectedTransactions(), in: context)
        selection.removeAll()
        recomputeTransferCandidates()
        recomputeMissingWork()
    }

    private func linkRefund() {
        LinkService.link(selectedTransactions(), kind: .refund, in: context)
        selection.removeAll()
        recomputeTransferCandidates()
        recomputeMissingWork()
    }

    private func unlinkSelection() {
        let groups = Set(selectedTransactions().compactMap { $0.linkGroupID })
        for gid in groups {
            LinkService.unlink(groupID: gid, in: allTransactions, context: context)
        }
        selection.removeAll()
        recomputeTransferCandidates()
        recomputeMissingWork()
    }

    /// Dim a linked partner that's only present for context.
    private func dim(_ tx: Transaction) -> Double { isContext(tx) ? 0.4 : 1 }

    private func linkGlyph(_ tx: Transaction) -> String {
        tx.linkKind == .refund ? "arrow.uturn.backward" : "arrow.left.arrow.right"
    }

    /// Tooltip for the link glyph: names the account(s) on the other side.
    private func linkHelp(_ tx: Transaction) -> String {
        guard let gid = tx.linkGroupID else { return "" }
        let noun = tx.linkKind == .refund ? "Refund" : "Transfer"
        let others = allTransactions
            .filter { $0.linkGroupID == gid && $0.id != tx.id }
            .compactMap { $0.account?.name }
        return others.isEmpty ? noun : "\(noun) with \(others.joined(separator: ", "))"
    }

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

/// A small red count "bubble" for overlaying on a toolbar glyph. Renders
/// nothing when `count` is zero.
private struct CountBubble: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(.red))
                .fixedSize()
        }
    }
}
