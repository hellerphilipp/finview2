import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ImportKit

/// Preferences tab for managing import specs (the YAML/CEL bank mappings).
/// Built-in banks are pre-installed; users augment them by dragging in a `.yaml`
/// file, choosing a file, or adding one by URL — enabling community specs and
/// DIY specs for unsupported banks.
struct ImportSpecsSettings: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ImportProfile.name) private var profiles: [ImportProfile]

    @State private var showingFileImporter = false
    @State private var showingURLPrompt = false
    @State private var urlText = ""
    @State private var status: Status?
    @State private var pendingDelete: ImportProfile?
    @State private var isTargeted = false

    private enum Status {
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone

            HStack {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Add from File…", systemImage: "doc.badge.plus")
                }
                Button {
                    urlText = ""
                    showingURLPrompt = true
                } label: {
                    Label("Add from URL…", systemImage: "link.badge.plus")
                }
                Spacer()
            }

            if let status {
                statusLine(status)
            }

            profileList
        }
        .padding(16)
        .fileImporter(isPresented: $showingFileImporter,
                      allowedContentTypes: [.yaml, .plainText, .text],
                      allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls): if let url = urls.first { add(from: url) }
            case let .failure(error): status = .failure(error.localizedDescription)
            }
        }
        .alert("Add spec from URL", isPresented: $showingURLPrompt) {
            TextField("https://example.com/mybank.yaml", text: $urlText)
                .textContentType(.URL)
            Button("Add") { addFromURLText() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The spec is downloaded once and stored in Tally.")
        }
        .confirmationDialog(
            "Remove this import spec?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let profile = pendingDelete { delete(profile) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            if let profile = pendingDelete, let count = profile.accounts?.count, count > 0 {
                Text("\(count) account\(count == 1 ? "" : "s") use “\(profile.name)”. They'll be left without an import profile.")
            }
        }
    }

    // MARK: Drop zone

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(height: 72)
            .overlay {
                Label("Drag a .yaml import spec here", systemImage: "square.and.arrow.down")
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                add(from: url)
                return true
            } isTargeted: { isTargeted = $0 }
    }

    // MARK: Profile list

    private var profileList: some View {
        List {
            ForEach(profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                        Text(usageText(for: profile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v\(profile.version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button {
                        confirmDelete(profile)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this spec")
                }
                .padding(.vertical, 2)
            }
        }
        .frame(minHeight: 140)
        .overlay {
            if profiles.isEmpty {
                Text("No import specs yet.").foregroundStyle(.secondary)
            }
        }
    }

    private func usageText(for profile: ImportProfile) -> String {
        let count = profile.accounts?.count ?? 0
        switch count {
        case 0: return "Not used by any account"
        case 1: return "Used by 1 account"
        default: return "Used by \(count) accounts"
        }
    }

    private func statusLine(_ status: Status) -> some View {
        switch status {
        case let .success(message):
            return Label(message, systemImage: "checkmark.circle").foregroundStyle(.green)
        case let .failure(message):
            return Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    // MARK: Actions

    private func add(from url: URL) {
        do {
            let yaml = try ImportProfileStore.fetchYAML(from: url)
            let profile = try ImportProfileStore.install(yaml: yaml, into: context)
            status = .success("Added “\(profile.name)”.")
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    private func addFromURLText() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            status = .failure("That doesn't look like a valid URL.")
            return
        }
        add(from: url)
    }

    private func confirmDelete(_ profile: ImportProfile) {
        if let count = profile.accounts?.count, count > 0 {
            pendingDelete = profile
        } else {
            delete(profile)
        }
    }

    private func delete(_ profile: ImportProfile) {
        let name = profile.name
        context.delete(profile)
        try? context.save()
        status = .success("Removed “\(name)”.")
    }
}
