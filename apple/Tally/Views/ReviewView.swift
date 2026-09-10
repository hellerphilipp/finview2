import SwiftUI
import SwiftData

/// Actions the Transaction menu-bar commands operate on. Published to the
/// scene via `focusedSceneValue` so menu items + shortcuts work app-wide.
@MainActor
final class ReviewActions: ObservableObject {
    var confirm: () -> Void = {}
    var reject: () -> Void = {}
    var toggleWork: () -> Void = {}
    var assignCategory: () -> Void = {}
    var acceptSuggestion: () -> Void = {}
    var hasSelection: Bool = false
}

struct ReviewFocusKey: FocusedValueKey {
    typealias Value = ReviewActions
}
extension FocusedValues {
    var reviewActions: ReviewActions? {
        get { self[ReviewFocusKey.self] }
        set { self[ReviewFocusKey.self] = newValue }
    }
}

struct ReviewView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Transaction> { $0.statusRaw == "pending" },
           sort: \Transaction.date, order: .reverse)
    private var pending: [Transaction]

    @Query private var merchants: [Merchant]
    @Query(sort: [SortDescriptor(\SpendingCategory.sortOrder)])
    private var categories: [SpendingCategory]

    @State private var selection = Set<UUID>()
    @State private var showingPalette = false
    @StateObject private var actions = ReviewActions()

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle",
                                       description: Text("No pending transactions to review."))
            } else {
                table
            }
        }
        .navigationTitle("Review")
        .toolbar { toolbarContent }
        .focusedSceneValue(\.reviewActions, actions)
        .onAppear { wireActions() }
        .onChange(of: selection) { actions.hasSelection = !selection.isEmpty }
        .sheet(isPresented: $showingPalette) {
            CategoryPalette(categories: categories) { assignCategory($0) }
        }
    }

    private var table: some View {
        Table(pending, selection: $selection) {
            TableColumn("Date") { Text(DateText.string($0.date)) }
                .width(min: 90, ideal: 100)
            TableColumn("Account") { Text($0.account?.name ?? "—") }
            TableColumn("Description") { Text($0.descriptionText).lineLimit(1) }
            TableColumn("Amount") { tx in
                Text(Money.string(tx.amount, currency: tx.account?.currencyCode ?? ""))
                    .monospacedDigit()
                    .foregroundStyle(tx.amount < 0 ? Color.primary : Color.green)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Category") { tx in CategoryCell(tx: tx, suggestion: suggestion(for: tx)) }
            TableColumn("Work") { tx in
                Image(systemName: tx.isWorkExpense ? "briefcase.fill" : "briefcase")
                    .foregroundStyle(tx.isWorkExpense ? Color.accentColor : Color.secondary)
                    .onTapGesture { tx.isWorkExpense.toggle(); try? context.save() }
            }
            .width(44)
        }
        .contextMenu(forSelectionType: UUID.self) { _ in
            Button("Assign Category…") { showingPalette = true }
            Button("Toggle Work Expense") { toggleWork() }
            Divider()
            Button("Confirm") { confirmSelection() }
            Button("Reject", role: .destructive) { rejectSelection() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
        }
    }

    // MARK: Suggestions

    private func suggestion(for tx: Transaction) -> SpendingCategory? {
        guard tx.category == nil else { return nil }
        return AutoTagger.suggest(for: tx.descriptionText, merchants: merchants)
    }

    // MARK: Actions

    private func selectedTransactions() -> [Transaction] {
        pending.filter { selection.contains($0.id) }
    }

    private func assignCategory(_ category: SpendingCategory) {
        for tx in selectedTransactions() {
            tx.category = category
            AutoTagger.learn(description: tx.descriptionText, category: category, in: context)
        }
        try? context.save()
    }

    private func acceptSuggestions() {
        for tx in selectedTransactions() {
            if let s = AutoTagger.suggest(for: tx.descriptionText, merchants: merchants) {
                tx.category = s
            }
        }
        try? context.save()
    }

    private func toggleWork() {
        let txs = selectedTransactions()
        let allWork = txs.allSatisfy(\.isWorkExpense)
        txs.forEach { $0.isWorkExpense = !allWork }
        try? context.save()
    }

    private func confirmSelection() { setStatus(.confirmed) }
    private func rejectSelection() { setStatus(.rejected) }

    private func setStatus(_ status: TransactionStatus) {
        selectedTransactions().forEach { $0.status = status }
        selection.removeAll()
        try? context.save()
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

// MARK: - Category cell

private struct CategoryCell: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\SpendingCategory.sortOrder)]) private var categories: [SpendingCategory]
    let tx: Transaction
    let suggestion: SpendingCategory?

    var body: some View {
        Menu {
            ForEach(topLevel) { parent in
                Button {
                    assign(parent)
                } label: { Label(parent.name, systemImage: parent.symbolName) }
                ForEach(children(of: parent)) { child in
                    Button("   \(child.name)") { assign(child) }
                }
            }
            if tx.category != nil {
                Divider()
                Button("Clear") { tx.category = nil; try? context.save() }
            }
        } label: {
            if let c = tx.category {
                Label(c.displayPath, systemImage: c.symbolName).foregroundStyle(Color(hex: c.colorHex))
            } else if let s = suggestion {
                Label("\(s.name)?", systemImage: "wand.and.stars")
                    .foregroundStyle(.secondary)
            } else {
                Text("Assign…").foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var topLevel: [SpendingCategory] { categories.filter { $0.parent == nil } }
    private func children(of parent: SpendingCategory) -> [SpendingCategory] {
        categories.filter { $0.parent?.persistentModelID == parent.persistentModelID }
    }
    private func assign(_ category: SpendingCategory) {
        tx.category = category
        AutoTagger.learn(description: tx.descriptionText, category: category, in: context)
        try? context.save()
    }
}

// MARK: - Category quick palette (⌘K)

struct CategoryPalette: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [SpendingCategory]
    let onPick: (SpendingCategory) -> Void

    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search categories…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            List(filtered) { category in
                Button {
                    onPick(category); dismiss()
                } label: {
                    Label(category.displayPath, systemImage: category.symbolName)
                        .foregroundStyle(Color(hex: category.colorHex))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 360, height: 420)
    }

    private var filtered: [SpendingCategory] {
        let sorted = categories.sorted { $0.displayPath < $1.displayPath }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.displayPath.localizedCaseInsensitiveContains(query) }
    }
}
