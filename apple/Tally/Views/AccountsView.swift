import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]

    @State private var editing: Account?
    @State private var showingNew = false

    var body: some View {
        Group {
            if accounts.isEmpty {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "building.columns")
                } description: {
                    Text("Add an account to start importing statements.")
                } actions: {
                    Button("Add Account…") { showingNew = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(accounts) { account in
                        AccountRow(account: account)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { editing = account }
                            .contextMenu {
                                Button("Edit…") { editing = account }
                                Button("Delete", role: .destructive) { context.delete(account) }
                            }
                    }
                    .onDelete { offsets in
                        offsets.map { accounts[$0] }.forEach(context.delete)
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Label("Add Account", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingNew) { AccountEditor(account: nil) }
        .sheet(item: $editing) { AccountEditor(account: $0) }
    }
}

private struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: account.colorHex)).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.headline)
                Text(account.institution.isEmpty ? "—" : account.institution)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(account.currencyCode).font(.callout.monospaced())
                Text(account.importProfile?.name ?? "No profile")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AccountEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ImportProfile.name) private var profiles: [ImportProfile]

    /// nil = creating a new account.
    let account: Account?

    @State private var name = ""
    @State private var institution = ""
    @State private var currencyCode = "CHF"
    @State private var colorHex = "#4C8BF5"
    @State private var selectedProfileID: PersistentIdentifier?

    private let currencies = ["CHF", "EUR", "USD", "GBP"]
    private let palette = ["#4C8BF5", "#34C759", "#FF9500", "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    TextField("Institution", text: $institution)
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(currencyList, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Import Profile") {
                    Picker("Profile", selection: $selectedProfileID) {
                        Text("None").tag(Optional<PersistentIdentifier>.none)
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(Optional(profile.persistentModelID))
                        }
                    }
                }
                Section("Color") {
                    HStack(spacing: 10) {
                        ForEach(palette, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: colorHex == hex ? 2 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(account == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 420, height: 420)
        .navigationTitle(account == nil ? "New Account" : "Edit Account")
        .onAppear(perform: load)
    }

    private var currencyList: [String] {
        currencies.contains(currencyCode) ? currencies : currencies + [currencyCode]
    }

    private func load() {
        if let account {
            name = account.name
            institution = account.institution
            currencyCode = account.currencyCode
            colorHex = account.colorHex
            selectedProfileID = account.importProfile?.persistentModelID
        } else {
            // Default a new account to the Swisscard profile if present.
            selectedProfileID = profiles.first { $0.name == "Swisscard" }?.persistentModelID
                ?? profiles.first?.persistentModelID
        }
    }

    private func save() {
        let profile = profiles.first { $0.persistentModelID == selectedProfileID }
        if let account {
            account.name = name
            account.institution = institution
            account.currencyCode = currencyCode
            account.colorHex = colorHex
            account.importProfile = profile
        } else {
            let new = Account(name: name, institution: institution,
                              currencyCode: currencyCode, colorHex: colorHex)
            new.importProfile = profile
            context.insert(new)
        }
        try? context.save()
        dismiss()
    }
}
