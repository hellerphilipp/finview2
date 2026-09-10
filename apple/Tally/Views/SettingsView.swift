import SwiftUI

struct SettingsView: View {
    @AppStorage("staleDays") private var staleDays = 35
    @AppStorage("defaultCurrency") private var defaultCurrency = "CHF"

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
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 240)
    }
}
