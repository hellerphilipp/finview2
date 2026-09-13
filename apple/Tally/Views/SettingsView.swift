import SwiftUI

struct SettingsView: View {
    @AppStorage("staleDays") private var staleDays = 35
    @AppStorage("defaultCurrency") private var defaultCurrency = "CHF"
    @AppStorage("showUnreviewedBadges") private var showUnreviewedBadges = true
    @AppStorage("showStatusBar") private var showStatusBar = false

    var body: some View {
        TabView {
            Form {
                Section("Imports") {
                    Stepper(value: $staleDays, in: 7...120, step: 1) {
                        Text("Warn when an account has no data for \(staleDays) days")
                    }
                    Picker("Default currency", selection: $defaultCurrency) {
                        ForEach(["CHF", "EUR", "USD", "GBP"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Sidebar") {
                    Toggle("Show count for unreviewed items", isOn: $showUnreviewedBadges)
                }
                Section("Transactions") {
                    Toggle("Show status bar", isOn: $showStatusBar)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            ImportSpecsSettings()
                .tabItem { Label("Import Specs", systemImage: "doc.text") }
        }
        .frame(width: 480, height: 440)
    }
}
