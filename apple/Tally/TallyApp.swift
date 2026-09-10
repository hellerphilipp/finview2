import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    let container: ModelContainer

    init() {
        let container = Persistence.makeContainer()
        Seeder.seedIfNeeded(container.mainContext)
        self.container = container
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .commands {
            TransactionCommands()
        }
    }
}

/// Menu-bar commands for the review workflow, wired to the focused Review
/// scene. Shortcuts work whenever the Review screen is active.
struct TransactionCommands: Commands {
    @FocusedValue(\.reviewActions) private var actions

    var body: some Commands {
        CommandMenu("Transaction") {
            Button("Assign Category…") { actions?.assignCategory() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(actions?.hasSelection != true)

            Button("Accept Suggested Category") { actions?.acceptSuggestion() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(actions?.hasSelection != true)

            Button("Toggle Work Expense") { actions?.toggleWork() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(actions?.hasSelection != true)

            Divider()

            Button("Confirm") { actions?.confirm() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(actions?.hasSelection != true)

            Button("Reject") { actions?.reject() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions?.hasSelection != true)
        }
    }
}
