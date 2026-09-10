import SwiftUI
import SwiftData

@main
struct TallyApp: App {
    let container: ModelContainer

    init() {
        if ProcessInfo.processInfo.environment["TALLY_UITEST"] == "1" {
            // UI-verification mode: fresh in-memory store with demo data.
            let container = Persistence.makeContainer(inMemory: true)
            DemoData.seed(container.mainContext)
            self.container = container
        } else {
            let container = Persistence.makeContainer()
            Seeder.seedIfNeeded(container.mainContext)
            self.container = container
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .defaultSize(width: 1150, height: 780)
        .commands {
            TransactionCommands()
            SampleDataCommands(context: container.mainContext)
        }

        Settings {
            SettingsView()
        }
        .modelContainer(container)
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

/// File-menu commands to load/remove example data for exploring the app.
struct SampleDataCommands: Commands {
    let context: ModelContext

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Load Sample Data") { DemoData.seed(context) }
            Button("Remove Sample Data") { DemoData.removeSamples(context) }
        }
    }
}
