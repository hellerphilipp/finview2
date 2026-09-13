import SwiftUI
import SwiftData

/// Actions the Transaction menu-bar commands operate on. Published to the
/// scene via `focusedSceneValue` so menu items + shortcuts work app-wide.
@MainActor
final class ReviewActions: ObservableObject {
    var confirm: () -> Void = {}
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

// MARK: - Category cell (inline category picker per row)

struct CategoryCell: View {
    @Environment(\.modelContext) private var context
    let tx: Transaction
    let categories: [SpendingCategory]
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
            label
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var label: some View {
        if let c = tx.category {
            Label(c.displayPath, systemImage: c.symbolName).foregroundStyle(Color(hex: c.colorHex))
        } else if let s = suggestion {
            Label("\(s.name)?", systemImage: "wand.and.stars").foregroundStyle(.secondary)
        } else {
            Text("Assign…").foregroundStyle(.tertiary)
        }
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
